package org.seplans.prolog;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Duration;
import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.stream.IntStream;

import org.junit.jupiter.api.Test;

/** How the bridge behaves when SWI-Prolog is missing, slow, busy or given nonsense. */
class SwiplProcessEngineTest {

	private static final String ONE_CHILD = "estate_cents(10000000).\nperson(p0, child).\n";

	private static SwiplProcessEngine engine(String command, Duration timeout, int maxConcurrent) throws Exception {
		return new SwiplProcessEngine(command, timeout, maxConcurrent, "256m");
	}

	@Test
	void answersWithJson() throws Exception {
		SwiplProcessEngine engine = engine("swipl", Duration.ofSeconds(10), 2);
		try {
			assertTrue(engine.solve(ONE_CHILD).contains("\"status\":\"ok\""));
			assertTrue(engine.version().contains("SWI-Prolog"));
		}
		finally {
			engine.destroy();
		}
	}

	@Test
	void missingProgramIsReportedClearly() throws Exception {
		SwiplProcessEngine engine = engine("no-such-prolog-program", Duration.ofSeconds(10), 2);
		try {
			PrologEngineException e = assertThrows(PrologEngineException.class, () -> engine.solve(ONE_CHILD));
			assertTrue(e.getMessage().contains("installed"), e.getMessage());
			assertThrows(PrologEngineException.class, engine::version);
		}
		finally {
			engine.destroy();
		}
	}

	@Test
	void slowComputationIsCutOff() throws Exception {
		// One millisecond is less than SWI-Prolog needs to start.
		SwiplProcessEngine engine = engine("swipl", Duration.ofMillis(1), 2);
		try {
			PrologEngineException e = assertThrows(PrologEngineException.class, () -> engine.solve(ONE_CHILD));
			assertTrue(e.getMessage().contains("did not answer"), e.getMessage());
		}
		finally {
			engine.destroy();
		}
	}

	@Test
	void inputThatIsNotPrologGivesAnErrorResultNotACrash() throws Exception {
		SwiplProcessEngine engine = engine("swipl", Duration.ofSeconds(10), 2);
		try {
			assertTrue(engine.solve("this is ( not prolog").contains("\"status\":\"error\""));
			assertTrue(engine.solve("halt.\n").contains("\"status\":\"invalid\""));
			assertTrue(engine.solve(":- shell('echo hacked').\n").contains("\"status\":\"invalid\""));
		}
		finally {
			engine.destroy();
		}
	}

	@Test
	void manyRequestsShareAFewProcesses() throws Exception {
		SwiplProcessEngine engine = engine("swipl", Duration.ofSeconds(30), 2);
		ExecutorService pool = Executors.newFixedThreadPool(8);
		try {
			List<Callable<String>> tasks = IntStream.range(0, 8)
					.<Callable<String>>mapToObj(i -> () -> engine.solve(ONE_CHILD)).toList();
			int answered = 0;
			for (Future<String> future : pool.invokeAll(tasks)) {
				assertTrue(future.get().contains("\"status\":\"ok\""));
				answered++;
			}
			assertEquals(8, answered);
		}
		finally {
			pool.shutdownNow();
			engine.destroy();
		}
	}
}
