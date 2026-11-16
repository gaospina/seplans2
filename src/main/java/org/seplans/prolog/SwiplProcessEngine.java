package org.seplans.prolog;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.DisposableBean;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

/**
 * Runs SWI-Prolog as a fresh process for each succession: facts go to standard input,
 * the JSON result comes back on standard output. Nothing is shared between requests.
 *
 * <p>Each process is bounded in time and memory, and only a fixed number run at once.
 */
@Component
public class SwiplProcessEngine implements PrologEngine, DisposableBean {

	private static final Logger log = LoggerFactory.getLogger(SwiplProcessEngine.class);

	private static final List<String> RULE_FILES = List.of("main.pl", "parameters.pl", "devolution.pl", "tax.pl");
	private static final int MAX_OUTPUT_BYTES = 4 * 1024 * 1024;

	private final String command;
	private final Duration timeout;
	private final String stackLimit;
	private final Semaphore permits;
	private final Path directory;
	private final Path mainFile;

	public SwiplProcessEngine(@Value("${seplans.swipl.command:swipl}") String command,
			@Value("${seplans.swipl.timeout:10s}") Duration timeout,
			@Value("${seplans.swipl.max-concurrent:4}") int maxConcurrent,
			@Value("${seplans.swipl.stack-limit:256m}") String stackLimit) throws IOException {
		this.command = command;
		this.timeout = timeout;
		this.stackLimit = stackLimit;
		this.permits = new Semaphore(Math.max(1, maxConcurrent), true);
		// swipl needs real files, and the rules may be inside a jar: copy them out once.
		this.directory = Files.createTempDirectory("seplans-prolog");
		for (String file : RULE_FILES) {
			try (InputStream in = new ClassPathResource("prolog/" + file).getInputStream()) {
				Files.copy(in, directory.resolve(file));
			}
		}
		this.mainFile = directory.resolve("main.pl");
	}

	/** Says at startup whether the engine is usable, instead of at the first request. */
	@EventListener(ApplicationReadyEvent.class)
	public void reportAvailability() {
		try {
			log.info("Rule engine ready: {}", version());
		}
		catch (PrologEngineException e) {
			log.error("Rule engine unavailable, every computation will fail: {}", e.getMessage());
		}
	}

	@Override
	public String version() {
		return run(List.of(command, "--version"), "", Duration.ofSeconds(10));
	}

	@Override
	public String solve(String facts) {
		try {
			// Waiting for a free slot counts against the same time budget as the computation.
			if (!permits.tryAcquire(timeout.toMillis(), TimeUnit.MILLISECONDS)) {
				throw new PrologEngineException("Too many computations are running; none finished within "
						+ describe(timeout) + ".");
			}
		}
		catch (InterruptedException e) {
			Thread.currentThread().interrupt();
			throw new PrologEngineException("Interrupted while waiting for a free rule engine.", e);
		}
		try {
			// -f none: ignore any user init file; -g run -t halt: run the entry point and exit.
			return run(List.of(command, "--stack-limit=" + stackLimit, "-f", "none", "-q", "-g", "run", "-t",
					"halt", mainFile.toString()), facts, timeout);
		}
		finally {
			permits.release();
		}
	}

	private String run(List<String> commandLine, String input, Duration limit) {
		Process process;
		try {
			process = new ProcessBuilder(new ArrayList<>(commandLine)).start();
		}
		catch (IOException e) {
			throw new PrologEngineException("Could not start '" + command + "'. Is SWI-Prolog installed and on the PATH?", e);
		}
		try {
			// Drain both pipes in the background so the process can never block on a full buffer.
			CompletableFuture<String> output = CompletableFuture.supplyAsync(() -> read(process.getInputStream()));
			CompletableFuture<String> errors = CompletableFuture.supplyAsync(() -> read(process.getErrorStream()));
			try (OutputStream stdin = process.getOutputStream()) {
				stdin.write(input.getBytes(StandardCharsets.UTF_8));
			}
			if (!process.waitFor(limit.toMillis(), TimeUnit.MILLISECONDS)) {
				throw new PrologEngineException("SWI-Prolog did not answer within " + describe(limit) + ".");
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
			// Also ends a process that overran its time; a no-op once it has exited.
			process.destroyForcibly();
		}
	}

	/** Reads at most {@link #MAX_OUTPUT_BYTES}, so a runaway process cannot exhaust memory. */
	private static String read(InputStream stream) {
		try (stream) {
			return new String(stream.readNBytes(MAX_OUTPUT_BYTES), StandardCharsets.UTF_8);
		}
		catch (IOException e) {
			throw new UncheckedIOException(e);
		}
	}

	private static String describe(Duration duration) {
		return duration.toMillis() < 1000 ? duration.toMillis() + " ms" : duration.toSeconds() + " s";
	}

	@Override
	public void destroy() {
		for (String file : RULE_FILES) {
			directory.resolve(file).toFile().delete();
		}
		directory.toFile().delete();
	}
}
