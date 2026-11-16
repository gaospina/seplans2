package org.seplans.service;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

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
	private static final int MAX_PERSONS = 100;
	private static final int MAX_NAME_LENGTH = 100;
	private static final Pattern PERSON_ID = Pattern.compile("\\bp(\\d+)\\b");

	private final PrologEngine engine;
	private final JsonMapper json;

	public SuccessionService(PrologEngine engine, JsonMapper json) {
		this.engine = engine;
		this.json = json;
	}

	public SuccessionResponse solve(SuccessionRequest request) {
		validate(request);
		List<PersonInput> persons = request.persons();
		EngineResult result = parse(engine.solve(facts(request)));
		return switch (result.status()) {
			case "ok" -> new SuccessionResponse("ok", result.note(), heirs(persons, result.heirs()),
					orEmpty(result.warnings()).stream().map(warning -> withNames(warning, persons)).toList(),
					result.usufructPercent());
			case "unsupported" -> SuccessionResponse.failure("unsupported", result.message());
			case "invalid" -> throw new InvalidRequestException(withNames(result.message(), persons));
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
		for (int i = 0; i < persons.size(); i++) {
			PersonInput person = persons.get(i);
			if (person == null || person.relation() == null) {
				throw new InvalidRequestException("Every relative needs a relationship.");
			}
			Integer via = person.via();
			if (person.relation().linkedByParent() && via != null && (via < 0 || via >= persons.size())) {
				throw new InvalidRequestException(name(persons, i) + ": the parent is not in the list.");
			}
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
			String id = id(i);
			facts.append("person(").append(id).append(", ").append(person.relation().atom()).append(").\n");
			if (person.isPredeceased()) {
				facts.append("predeceased(").append(id).append(").\n");
			}
			if (person.relation().linkedByParent() && person.via() != null) {
				facts.append("via(").append(id).append(", ").append(id(person.via())).append(").\n");
			}
			if (person.relation().needsLine() && person.line() != null) {
				facts.append("line(").append(id).append(", ").append(person.line().atom()).append(").\n");
			}
			if (person.isCommonChild()) {
				facts.append("common_child(").append(id).append(").\n");
			}
			if (person.isDisabled()) {
				facts.append("disabled(").append(id).append(").\n");
			}
			if (person.isExemptSibling()) {
				facts.append("exempt_sibling(").append(id).append(").\n");
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

	private static String name(List<PersonInput> persons, int index) {
		String name = persons.get(index).name();
		if (name == null || name.isBlank()) {
			return "Person " + (index + 1);
		}
		name = name.strip();
		return name.length() > MAX_NAME_LENGTH ? name.substring(0, MAX_NAME_LENGTH) : name;
	}

	/** The rule base names people by identifier; show the names the user typed instead. */
	private static String withNames(String message, List<PersonInput> persons) {
		if (message == null) {
			return null;
		}
		Matcher matcher = PERSON_ID.matcher(message);
		return matcher.replaceAll(match -> {
			int index = Integer.parseInt(match.group(1));
			return Matcher.quoteReplacement(index < persons.size() ? name(persons, index) : match.group());
		});
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
			heirs.add(new HeirResult(name(persons, i), persons.get(i).relation(), heir.heir(), heir.right(),
					heir.fraction(), euros(heir.valueCents()), heir.taxStatus(), euros(heir.allowanceCents()),
					euros(heir.taxableCents()), euros(heir.taxCents()), euros(heir.netCents()), heir.basis(),
					heir.taxBasis(),
					orEmpty(heir.allowanceParts()).stream()
							.map(part -> new HeirResult.AllowancePart(part.label(), euros(part.cents()))).toList(),
					orEmpty(heir.brackets()).stream().map(slice -> new HeirResult.Bracket(euros(slice.fromCents()),
							euros(slice.toCents()), slice.rate(), euros(slice.taxCents()))).toList()));
		}
		return heirs;
	}

	private static <T> List<T> orEmpty(List<T> list) {
		return list == null ? List.of() : list;
	}

	private static BigDecimal euros(Long cents) {
		return cents == null ? null : BigDecimal.valueOf(cents, 2);
	}

	/** The JSON object written by main.pl. */
	record EngineResult(String status, String message, String note, List<EngineHeir> heirs, List<String> warnings,
			Integer usufructPercent) {
	}

	record EngineHeir(String id, boolean heir, String right, String fraction, Long valueCents, String taxStatus,
			Long allowanceCents, Long taxableCents, Long taxCents, Long netCents, String basis, String taxBasis,
			List<EnginePart> allowanceParts, List<EngineSlice> brackets) {
	}

	record EnginePart(String label, Long cents) {
	}

	record EngineSlice(Long fromCents, Long toCents, int rate, Long taxCents) {
	}
}
