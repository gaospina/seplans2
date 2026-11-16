package org.seplans.web;

import org.seplans.api.SuccessionRequest;
import org.seplans.api.SuccessionResponse;
import org.seplans.prolog.PrologEngineException;
import org.seplans.service.InvalidRequestException;
import org.seplans.service.SuccessionService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class SuccessionController {

	private static final Logger log = LoggerFactory.getLogger(SuccessionController.class);

	private final SuccessionService service;

	public SuccessionController(SuccessionService service) {
		this.service = service;
	}

	@PostMapping("/succession")
	public SuccessionResponse solve(@RequestBody SuccessionRequest request) {
		return service.solve(request);
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
		return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
				.body(SuccessionResponse.failure("error", "The rule engine could not compute this succession."));
	}
}
