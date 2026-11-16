package org.seplans;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.Test;

/** Runs the plunit suite of the rule base, so that a plain Maven build covers the Prolog rules. */
class PrologRulesTest {

	@Test
	void plunitSuitePasses() throws Exception {
		Process process = new ProcessBuilder("swipl", "-q", "-g", "run_tests", "-t", "halt",
				"src/test/prolog/succession_tests.pl").redirectErrorStream(true).start();
		process.getOutputStream().close();
		String output = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
		assertTrue(process.waitFor(60, TimeUnit.SECONDS), "plunit did not finish");
		assertEquals(0, process.exitValue(), output);
	}
}
