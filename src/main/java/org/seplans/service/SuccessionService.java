package org.seplans.service;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

import org.seplans.api.HeirResult;
import org.seplans.api.PersonInput;
import org.seplans.api.SuccessionRequest;
import org.seplans.api.SuccessionResponse;
import org.seplans.prolog.PrologEngine;
import org.seplans.prolog.PrologEngineException;
import org.springframework.stereotype.Service;

import tools.jackson.core.JacksonException;
import tools.jackson.databind.json.JsonMapper;

/**
 * Turns a request into Prolog facts, asks the engine, and turns the answer back into a
 * response. All legal reasoning stays in Prolog; this class only checks that the input is
 * well formed.
 */
@Service
public class SuccessionService {

	private static final BigDecimal MAX_ESTATE = new BigDecimal("1000000000000");
	private static final int MAX_PERSONS = 50;

	private final PrologEngine engine;
	private final JsonMapper json;

	public SuccessionService(PrologEngine engine, JsonMapper json) {
		this.engine = engine;
		this.json = json;
	}

	public SuccessionResponse solve(SuccessionRequest request) {
		validate(request);
		EngineResult result = parse(engine.solve(facts(request)));
		return switch (result.status()) {
			case "ok" -> new SuccessionResponse("ok", null, heirs(request.persons(), result.heirs()));
			case "unsupported" -> SuccessionResponse.failure("unsupported", result.message());
			case "invalid" -> throw new InvalidRequestException(result.message());
			default -> throw new PrologEngineException("The rule base reported an error: " + result.message());
		};
	}

	private static void validate(SuccessionRequest request) {
		BigDecimal estate = request.estate();
		if (estate == null || estate.signum() <= 0) {
			throw new InvalidRequestException("The estate amount must be greater than zero.");
		}
		if (estate.stripTrailingZeros().scale() > 2 || estate.compareTo(MAX_ESTATE) > 0) {
			throw new InvalidRequestException("The estate amount must be in euros and cents, up to " + MAX_ESTATE.toPlainString() + ".");
		}
		List<PersonInput> persons = request.persons();
		if (persons == null || persons.isEmpty()) {
			throw new InvalidRequestException("List at least one relative.");
		}
		if (persons.size() > MAX_PERSONS) {
			throw new InvalidRequestException("At most " + MAX_PERSONS + " relatives can be listed.");
		}
		if (persons.stream().anyMatch(p -> p == null || p.relation() == null)) {
			throw new InvalidRequestException("Every relative needs a relationship.");
		}
		Integer age = request.spouseAge();
		if (age != null && (age < 0 || age > 130)) {
			throw new InvalidRequestException("The spouse's age is not plausible.");
		}
	}

	/**
	 * Builds the Prolog clauses. Only generated identifiers, enum atoms and integers are
	 * written, never text typed by the user, so the input cannot inject Prolog code.
	 */
	static String facts(SuccessionRequest request) {
		StringBuilder facts = new StringBuilder();
		facts.append("estate_cents(").append(request.estate().movePointRight(2).toBigIntegerExact()).append(").\n");
		List<PersonInput> persons = request.persons();
		for (int i = 0; i < persons.size(); i++) {
			PersonInput person = persons.get(i);
			facts.append("person(").append(id(i)).append(", ").append(person.relation().atom()).append(").\n");
			if (person.isCommonChild()) {
				facts.append("common_child(").append(id(i)).append(").\n");
			}
		}
		if (request.spouseAge() != null) {
			facts.append("spouse_age(").append(request.spouseAge().intValue()).append(").\n");
		}
		if (request.spouseOption() != null) {
			facts.append("spouse_option(").append(request.spouseOption().atom()).append(").\n");
		}
		return facts.toString();
	}

	private static String id(int index) {
		return "p" + index;
	}

	private EngineResult parse(String output) {
		try {
			EngineResult result = json.readValue(output, EngineResult.class);
			if (result == null || result.status() == null) {
				throw new PrologEngineException("The rule base gave an answer without a status.");
			}
			return result;
		}
		catch (JacksonException e) {
			throw new PrologEngineException("The rule base gave an answer that is not valid JSON.", e);
		}
	}

	private static List<HeirResult> heirs(List<PersonInput> persons, List<EngineHeir> engineHeirs) {
		List<HeirResult> heirs = new ArrayList<>();
		for (int i = 0; i < persons.size(); i++) {
			String id = id(i);
			EngineHeir heir = engineHeirs.stream().filter(h -> id.equals(h.id())).findFirst()
					.orElseThrow(() -> new PrologEngineException("The rule base gave no answer for " + id + "."));
			PersonInput person = persons.get(i);
			String name = person.name() == null || person.name().isBlank() ? "Person " + (i + 1) : person.name().strip();
			heirs.add(new HeirResult(name, person.relation(), heir.heir(), heir.right(), heir.fraction(),
					euros(heir.valueCents()), euros(heir.allowanceCents()), euros(heir.taxableCents()),
					euros(heir.taxCents()), euros(heir.netCents()), heir.basis(), heir.taxBasis()));
		}
		return heirs;
	}

	private static BigDecimal euros(Long cents) {
		return cents == null ? null : BigDecimal.valueOf(cents, 2);
	}

	/** The JSON object written by main.pl. */
	record EngineResult(String status, String message, List<EngineHeir> heirs) {
	}

	record EngineHeir(String id, boolean heir, String right, String fraction, Long valueCents, Long allowanceCents,
			Long taxableCents, Long taxCents, Long netCents, String basis, String taxBasis) {
	}
}
