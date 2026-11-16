package org.seplans.prolog;

public class PrologEngineException extends RuntimeException {

	public PrologEngineException(String message) {
		super(message);
	}

	public PrologEngineException(String message, Throwable cause) {
		super(message, cause);
	}
}
