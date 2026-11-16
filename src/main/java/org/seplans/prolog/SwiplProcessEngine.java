package org.seplans.prolog;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

/**
 * Runs SWI-Prolog as a fresh process for each succession: facts go to standard input,
 * the JSON result comes back on standard output. Nothing is shared between requests.
 */
@Component
public class SwiplProcessEngine implements PrologEngine {

	private static final List<String> RULE_FILES = List.of("main.pl", "parameters.pl", "devolution.pl", "tax.pl");

	private final String command;
	private final Duration timeout;
	private final Path mainFile;

	public SwiplProcessEngine(@Value("${seplans.swipl.command:swipl}") String command,
			@Value("${seplans.swipl.timeout:10s}") Duration timeout) throws IOException {
		this.command = command;
		this.timeout = timeout;
		// swipl needs real files, and the rules may be inside a jar: copy them out once.
		Path directory = Files.createTempDirectory("seplans-prolog");
		for (String file : RULE_FILES) {
			try (InputStream in = new ClassPathResource("prolog/" + file).getInputStream()) {
				Files.copy(in, directory.resolve(file));
			}
		}
		this.mainFile = directory.resolve("main.pl");
	}

	@Override
	public String solve(String facts) {
		Process process;
		try {
			process = new ProcessBuilder(command, "-q", "-g", "run", "-t", "halt", mainFile.toString()).start();
		}
		catch (IOException e) {
			throw new PrologEngineException("Could not start '" + command + "'. Is SWI-Prolog installed and on the PATH?", e);
		}
		try {
			// Drain both pipes in the background so the process can never block on a full buffer.
			CompletableFuture<String> output = CompletableFuture.supplyAsync(() -> read(process.getInputStream()));
			CompletableFuture<String> errors = CompletableFuture.supplyAsync(() -> read(process.getErrorStream()));
			try (OutputStream stdin = process.getOutputStream()) {
				stdin.write(facts.getBytes(StandardCharsets.UTF_8));
			}
			if (!process.waitFor(timeout.toMillis(), TimeUnit.MILLISECONDS)) {
				throw new PrologEngineException("SWI-Prolog did not answer within " + timeout.toSeconds() + " s.");
			}
			String result = output.get(5, TimeUnit.SECONDS).strip();
			if (process.exitValue() != 0 || result.isEmpty()) {
				throw new PrologEngineException("SWI-Prolog failed (exit code " + process.exitValue() + "): "
						+ errors.get(5, TimeUnit.SECONDS).strip());
			}
			return result;
		}
		catch (InterruptedException e) {
			Thread.currentThread().interrupt();
			throw new PrologEngineException("Interrupted while waiting for SWI-Prolog.", e);
		}
		catch (PrologEngineException e) {
			throw e;
		}
		catch (Exception e) {
			throw new PrologEngineException("Could not exchange data with SWI-Prolog.", e);
		}
		finally {
			process.destroyForcibly();
		}
	}

	private static String read(InputStream stream) {
		try (stream) {
			return new String(stream.readAllBytes(), StandardCharsets.UTF_8);
		}
		catch (IOException e) {
			throw new UncheckedIOException(e);
		}
	}
}
