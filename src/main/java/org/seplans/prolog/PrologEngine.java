package org.seplans.prolog;

/** The bridge to the Prolog rule base. */
public interface PrologEngine {

	/**
	 * Solves one succession.
	 *
	 * @param facts the succession as Prolog clauses (see devolution.pl)
	 * @return the result as a JSON object (see main.pl)
	 * @throws PrologEngineException if the engine could not be run or gave no answer
	 */
	String solve(String facts);
}
