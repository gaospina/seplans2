package org.seplans.service;

/** The succession as described cannot be solved; the message says what to correct. */
public class InvalidRequestException extends RuntimeException {

	public InvalidRequestException(String message) {
		super(message);
	}
}
