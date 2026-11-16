package org.seplans.web;

import org.seplans.api.SuccessionRequest;
import org.seplans.api.SuccessionResponse;
import java.util.Map;

import org.seplans.prolog.PrologEngine;
import org.seplans.prolog.PrologEngineException;
import org.seplans.service.InvalidRequestException;
import org.seplans.service.SuccessionService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class SuccessionController {

	private static final Logger log = LoggerFactory.getLogger(SuccessionController.class);

	private final SuccessionService service;
	private final PrologEngine engine;

	public SuccessionController(SuccessionService service, PrologEngine engine) {
		this.service = service;
		this.engine = engine;
	}

	@PostMapping("/succession")
	public SuccessionResponse solve(@RequestBody SuccessionRequest request) {
		return service.solve(request);
	}

	/** Reports whether the rule engine can be run. */
	@GetMapping("/health")
	public Map<String, String> health() {
		return Map.of("status", "ok", "engine", engine.version());
	}

	@ExceptionHandler(InvalidRequestException.class)
	ResponseEntity<SuccessionResponse> invalid(InvalidRequestException e) {
		return ResponseEntity.badRequest().body(SuccessionResponse.failure("invalid", e.getMessage()));
	}

	@ExceptionHandler(HttpMessageNotReadableException.class)
	ResponseEntity<SuccessionResponse> unreadable(HttpMessageNotReadableException e) {
		log.debug("Unreadable request", e);
		return ResponseEntity.badRequest().body(SuccessionResponse.failure("invalid", "The request could not be read."));
	}

	@ExceptionHandler(PrologEngineException.class)
	ResponseEntity<SuccessionResponse> engineFailure(PrologEngineException e) {
		log.error("Prolog engine failure", e);
		return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
				.body(SuccessionResponse.failure("error", "The rule engine could not answer. Please try again later."));
	}
}
