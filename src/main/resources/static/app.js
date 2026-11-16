"use strict";

const RELATION_GROUPS = [
  ["Partner", {
    SPOUSE: "Spouse",
    PACS_PARTNER: "PACS partner",
    COHABITANT: "Cohabitant"
  }],
  ["Descendants", {
    CHILD: "Child",
    DESCENDANT: "Grandchild or further descendant"
  }],
  ["Parents, brothers and sisters", {
    FATHER: "Father",
    MOTHER: "Mother",
    SIBLING: "Brother / sister",
    SIBLING_DESCENDANT: "Nephew / niece or their descendant"
  }],
  ["Other ascendants", {
    GRANDPARENT: "Grandparent",
    GREAT_GRANDPARENT: "Great-grandparent"
  }],
  ["Other collaterals", {
    UNCLE_AUNT: "Uncle / aunt",
    GREAT_UNCLE_AUNT: "Great-uncle / great-aunt",
    FIRST_COUSIN: "First cousin",
    COLLATERAL_5: "Other collateral, 5th degree",
    COLLATERAL_6: "Other collateral, 6th degree"
  }]
];
const RELATIONS = Object.assign({}, ...RELATION_GROUPS.map(([, relations]) => relations));
const RIGHTS = { full: "Full ownership", usufruct: "Usufruct", bare: "Bare ownership" };

// Which listed relatives can be the parent of a person related "via" someone.
const PARENT_RELATIONS = {
  DESCENDANT: ["CHILD", "DESCENDANT"],
  SIBLING_DESCENDANT: ["SIBLING", "SIBLING_DESCENDANT"]
};
// Relatives who may be listed although they died first, because they can be represented.
const CAN_BE_REPRESENTED = ["CHILD", "DESCENDANT", "SIBLING", "SIBLING_DESCENDANT"];
// Relatives who never inherit without a will, or never pay tax: no tax questions for them.
const NO_TAX_QUESTIONS = ["SPOUSE", "PACS_PARTNER", "COHABITANT"];
const NEEDS_LINE = ["GRANDPARENT", "GREAT_GRANDPARENT", "UNCLE_AUNT", "GREAT_UNCLE_AUNT",
  "FIRST_COUSIN", "COLLATERAL_5", "COLLATERAL_6"];

// Ready-made families. "via" is the position of the parent in the list.
const EXAMPLES = [
  { label: "Spouse and two common children (usufruct)", estate: 600000, option: "USUFRUCT", age: 65,
    persons: [
      { name: "Claire", relation: "SPOUSE" },
      { name: "Luc", relation: "CHILD", common: true },
      { name: "Emma", relation: "CHILD", common: true }] },
  { label: "Blended family: spouse, one common child, one from a first marriage", estate: 500000,
    persons: [
      { name: "Claire", relation: "SPOUSE" },
      { name: "Luc", relation: "CHILD", common: true },
      { name: "Hugo", relation: "CHILD", common: false }] },
  { label: "Grandchildren in place of a child who died", estate: 600000,
    persons: [
      { name: "Luc", relation: "CHILD" },
      { name: "Anne", relation: "CHILD", predeceased: true },
      { name: "Zoé", relation: "DESCENDANT", via: 1 },
      { name: "Tom", relation: "DESCENDANT", via: 1 }] },
  { label: "No children: father, a brother, and a nephew for a sister who died", estate: 400000,
    persons: [
      { name: "Jean", relation: "FATHER" },
      { name: "Marc", relation: "SIBLING" },
      { name: "Ève", relation: "SIBLING", predeceased: true },
      { name: "Noa", relation: "SIBLING_DESCENDANT", via: 2 }] },
  { label: "Distant relatives: an uncle and two cousins", estate: 300000,
    persons: [
      { name: "Paul", relation: "UNCLE_AUNT", line: "PATERNAL" },
      { name: "Léa", relation: "FIRST_COUSIN", line: "MATERNAL" },
      { name: "Inès", relation: "FIRST_COUSIN", line: "MATERNAL", disabled: true }] }
];

const form = document.getElementById("form");
const estateInput = document.getElementById("estate");
const ageInput = document.getElementById("spouse-age");
const personsBody = document.querySelector("#persons tbody");
const spouseSection = document.getElementById("spouse-section");
const optionBlock = document.getElementById("option-block");
const ageBlock = document.getElementById("age-block");
const message = document.getElementById("message");
const result = document.getElementById("result");
const exampleSelect = document.getElementById("example");
const euro = new Intl.NumberFormat("en-IE", { style: "currency", currency: "EUR" });

let nextUid = 1;

// --- building the form --------------------------------------------------------

function labelled(text, control, before) {
  const label = document.createElement("label");
  if (before) label.append(text, control); else label.append(control, " " + text);
  return label;
}

function checkbox(className, checked) {
  const input = document.createElement("input");
  input.type = "checkbox";
  input.className = className;
  input.checked = Boolean(checked);
  return input;
}

function addPerson(person = {}) {
  const row = document.createElement("tr");
  row.dataset.uid = String(nextUid++);

  const nameInput = document.createElement("input");
  nameInput.type = "text";
  nameInput.className = "name";
  nameInput.value = person.name || "";
  nameInput.setAttribute("aria-label", "Name");

  const select = document.createElement("select");
  select.className = "relation";
  select.setAttribute("aria-label", "Relationship");
  for (const [group, relations] of RELATION_GROUPS) {
    const optgroup = document.createElement("optgroup");
    optgroup.label = group;
    for (const [value, label] of Object.entries(relations)) {
      optgroup.append(new Option(label, value, false, value === (person.relation || "CHILD")));
    }
    select.append(optgroup);
  }

  const via = document.createElement("select");
  via.className = "via";

  const line = document.createElement("select");
  line.className = "line";
  line.add(new Option("Choose…", ""));
  line.add(new Option("Father's side", "PATERNAL"));
  line.add(new Option("Mother's side", "MATERNAL"));
  line.value = person.line || "";

  const predeceased = checkbox("predeceased", person.predeceased);
  const common = checkbox("common", person.common !== false);
  const disabled = checkbox("disabled", person.disabled);
  const exempt = checkbox("exempt", person.exempt);

  const none = document.createElement("span");
  none.className = "none";
  none.textContent = "—";

  const remove = document.createElement("button");
  remove.type = "button";
  remove.className = "remove";
  remove.textContent = "Remove";
  remove.addEventListener("click", () => { row.remove(); refresh(); });

  row.insertCell().append(nameInput);
  row.insertCell().append(select);
  const details = row.insertCell();
  details.className = "details";
  details.append(
    labelled("Child of", via, true),
    labelled("Side", line, true),
    labelled("Died before the deceased", predeceased),
    labelled("Also the spouse's child", common),
    labelled("Disabled", disabled),
    labelled("Lived with the deceased (tax exemption)", exempt),
    none);
  disabled.closest("label").title =
    "Unable to work in normal conditions because of a physical or mental impairment: adds a 159 325 € allowance (CGI art. 779 II).";
  exempt.closest("label").title =
    "Exempt if all three hold at the death: single, widowed, divorced or separated; over 50 or unable to work; lived with the deceased for the previous five years (CGI art. 796-0 ter).";
  row.insertCell().append(remove);

  nameInput.addEventListener("input", refresh);
  personsBody.append(row);
  return row;
}

function rows() {
  return [...personsBody.rows].map((row, index) => ({
    row,
    uid: row.dataset.uid,
    name: row.querySelector(".name").value.trim() || "Person " + (index + 1),
    rawName: row.querySelector(".name").value,
    relation: row.querySelector(".relation").value,
    predeceased: row.querySelector(".predeceased").checked,
    via: row.querySelector(".via").value,
    line: row.querySelector(".line").value,
    common: row.querySelector(".common").checked,
    disabled: row.querySelector(".disabled").checked,
    exempt: row.querySelector(".exempt").checked
  }));
}

/** Shows only the questions that matter for the family currently listed. */
function refresh() {
  const list = rows();
  const hasSpouse = list.some(p => p.relation === "SPOUSE");

  for (const person of list) {
    const { row, relation } = person;
    const parents = PARENT_RELATIONS[relation];
    const canDie = CAN_BE_REPRESENTED.includes(relation);
    const dead = canDie && person.predeceased;
    const show = {
      via: Boolean(parents),
      line: NEEDS_LINE.includes(relation),
      predeceased: canDie,
      common: relation === "CHILD" && hasSpouse,
      disabled: !NO_TAX_QUESTIONS.includes(relation) && !dead,
      exempt: relation === "SIBLING" && !dead
    };

    // Rebuild the list of possible parents, keeping the current choice if still valid.
    const via = row.querySelector(".via");
    const wanted = row.dataset.via || person.via;
    const candidates = parents ? list.filter(p => p.uid !== person.uid && parents.includes(p.relation)) : [];
    via.replaceChildren(new Option(candidates.length ? "Choose…" : "Add the parent first", ""));
    for (const candidate of candidates) {
      via.add(new Option(candidate.name, candidate.uid, false, candidate.uid === wanted));
    }
    delete row.dataset.via;

    for (const [name, visible] of Object.entries(show)) {
      row.querySelector("." + name).closest("label").hidden = !visible;
    }
    row.querySelector(".none").hidden = Object.values(show).some(Boolean);
  }

  // The spouse's option exists when every child who inherits or is represented is common.
  const current = rows();
  const represented = new Set(current.map(p => p.via).filter(Boolean));
  const stems = current.filter(p => p.relation === "CHILD" && (!p.predeceased || represented.has(p.uid)));
  const optionApplies = hasSpouse && stems.length > 0 && stems.every(p => p.common);
  spouseSection.hidden = !optionApplies;
  ageBlock.hidden = !(optionApplies && form.elements.option.value === "USUFRUCT");
}

function clearForm() {
  personsBody.replaceChildren();
  estateInput.value = "";
  ageInput.value = "";
  for (const radio of form.elements.option) radio.checked = false;
  clearProblems();
  result.hidden = true;
}

function loadExample(example) {
  clearForm();
  estateInput.value = example.estate;
  const added = example.persons.map(person => addPerson(person));
  example.persons.forEach((person, i) => {
    if (person.via !== undefined) added[i].dataset.via = added[person.via].dataset.uid;
  });
  if (example.option) form.elements.option.value = example.option;
  if (example.age) ageInput.value = example.age;
  refresh();
}

// --- checking the input before sending ---------------------------------------

function clearProblems() {
  message.hidden = true;
  message.replaceChildren();
  for (const element of form.querySelectorAll("[aria-invalid]")) element.removeAttribute("aria-invalid");
}

function showProblems(problems) {
  const list = document.createElement("ul");
  for (const problem of problems) {
    if (problem.element) problem.element.setAttribute("aria-invalid", "true");
    const item = document.createElement("li");
    item.textContent = problem.text;
    list.append(item);
  }
  message.replaceChildren(problems.length === 1 ? problems[0].text : "Please correct the following:");
  if (problems.length > 1) message.append(list);
  message.hidden = false;
  const first = problems.find(p => p.element);
  if (first) (first.element.matches("fieldset") ? first.element.querySelector("input") : first.element).focus();
  else message.scrollIntoView({ block: "nearest" });
}

/** Problems the page can see for itself; the rule base checks the rest. */
function findProblems(list) {
  const problems = [];
  const estate = Number(estateInput.value);
  if (estateInput.value === "" || !(estate > 0)) {
    problems.push({ element: estateInput, text: "Enter the net estate, an amount greater than zero." });
  }
  if (list.length === 0) {
    problems.push({ element: document.getElementById("add"), text: "Add at least one relative." });
  }
  for (const person of list) {
    if (PARENT_RELATIONS[person.relation] && !person.via) {
      problems.push({ element: person.row.querySelector(".via"),
        text: person.name + ": choose whose child this person is. Add the parent to the list first if needed, even if they died before the deceased." });
    }
    if (NEEDS_LINE.includes(person.relation) && !person.line) {
      problems.push({ element: person.row.querySelector(".line"),
        text: person.name + ": say whether this relative is on the father's or the mother's side." });
    }
  }
  for (const relation of ["SPOUSE", "FATHER", "MOTHER"]) {
    const same = list.filter(p => p.relation === relation);
    if (same.length > 1) {
      problems.push({ element: same[1].row.querySelector(".relation"),
        text: "There can be only one " + RELATIONS[relation].toLowerCase() + "." });
    }
  }
  if (!spouseSection.hidden && !form.elements.option.value) {
    problems.push({ element: optionBlock, text: "Choose the spouse's option." });
  }
  if (!ageBlock.hidden) {
    const age = Number(ageInput.value);
    if (ageInput.value === "" || !Number.isInteger(age) || age < 0 || age > 130) {
      problems.push({ element: ageInput, text: "Enter the spouse's age in whole years." });
    }
  }
  return problems;
}

// --- showing the result -------------------------------------------------------

function money(value) {
  return value === null || value === undefined ? "—" : euro.format(value);
}

function cell(row, text, numeric) {
  const td = row.insertCell();
  td.textContent = text;
  if (numeric) td.className = "num";
  return td;
}

function line(table, label, amount, className) {
  const row = table.insertRow();
  if (className) row.className = className;
  cell(row, label);
  cell(row, amount, true);
}

function explanation(heir, usufructPercent) {
  const details = document.createElement("details");
  const summary = document.createElement("summary");
  const outcome = document.createElement("span");
  outcome.textContent = heir.heir
    ? " — " + RIGHTS[heir.right].toLowerCase() + " of " + heir.fraction + ", " + money(heir.tax) + " tax"
    : " — not an heir";
  summary.append(heir.name, outcome);

  const body = document.createElement("div");
  body.className = "body";
  const why = document.createElement("p");
  why.textContent = heir.basis;
  body.append(why);

  if (heir.heir) {
    const tax = document.createElement("p");
    tax.textContent = heir.taxBasis;
    body.append(tax);

    const table = document.createElement("table");
    let valueLabel = "Share: " + heir.fraction + " of the estate";
    if (heir.right === "usufruct") valueLabel += ", usufruct valued at " + usufructPercent + " %";
    if (heir.right === "bare") valueLabel += ", bare ownership valued at " + (100 - usufructPercent) + " %";
    line(table, valueLabel, money(heir.value));
    if (heir.taxStatus === "exempt") {
      line(table, "Tax", "Exempt");
    } else {
      for (const part of heir.allowanceParts) line(table, part.label, money(part.amount), "sub");
      const entitled = heir.allowanceParts.reduce((sum, part) => sum + part.amount, 0);
      line(table, entitled > heir.allowance ? "Allowance applied, limited to the share" : "Allowance applied",
        "− " + money(heir.allowance));
      line(table, "Taxable amount", money(heir.taxable), "total");
      for (const bracket of heir.brackets) {
        line(table, money(bracket.from) + " to " + money(bracket.to) + " at " + bracket.rate + " %",
          money(bracket.tax), "sub");
      }
      line(table, "Tax", money(heir.tax), "total");
    }
    line(table, "Net received", money(heir.net), "total");
    body.append(table);
  }
  details.append(summary, body);
  return details;
}

function showResult(response, estate) {
  const body = document.querySelector("#heirs tbody");
  const explanations = document.getElementById("explanations");
  body.replaceChildren();
  explanations.replaceChildren();

  let totalTax = 0;
  for (const heir of response.heirs) {
    const row = body.insertRow();
    cell(row, heir.name);
    cell(row, RELATIONS[heir.relation]);
    if (heir.heir) {
      cell(row, RIGHTS[heir.right]);
      cell(row, heir.fraction, true);
      cell(row, money(heir.value), true);
      cell(row, heir.taxStatus === "exempt" ? "Exempt" : money(heir.allowance), true);
      cell(row, money(heir.taxable), true);
      cell(row, money(heir.tax), true);
      cell(row, money(heir.net), true);
      totalTax += heir.tax;
    } else {
      row.className = "not-heir";
      cell(row, "Not an heir");
      for (let i = 0; i < 6; i++) cell(row, "—", true);
    }
    explanations.append(explanation(heir, response.usufructPercent));
  }

  const anyHeir = response.heirs.some(heir => heir.heir);
  document.getElementById("sum-estate").textContent = money(estate);
  document.getElementById("sum-tax").textContent = money(totalTax);
  document.getElementById("sum-net").textContent = anyHeir ? money(estate - totalTax) : money(0);

  const note = document.getElementById("note");
  note.textContent = response.message || "";
  note.hidden = !response.message;

  const warnings = document.getElementById("warnings");
  warnings.replaceChildren(...response.warnings.map(text => {
    const item = document.createElement("li");
    item.textContent = text;
    return item;
  }));
  warnings.hidden = response.warnings.length === 0;

  const valuation = document.getElementById("valuation-note");
  valuation.hidden = response.usufructPercent === null;
  if (response.usufructPercent !== null) {
    valuation.textContent = "At the spouse's age the usufruct is worth " + response.usufructPercent
      + " % of full ownership and the bare ownership " + (100 - response.usufructPercent)
      + " % (CGI art. 669). The values above use this valuation.";
  }

  result.hidden = false;
  result.scrollIntoView({ behavior: "smooth", block: "start" });
}

async function submit(event) {
  event.preventDefault();
  clearProblems();
  result.hidden = true;

  const list = rows();
  const problems = findProblems(list);
  if (problems.length > 0) {
    showProblems(problems);
    return;
  }

  const hasSpouse = list.some(p => p.relation === "SPOUSE");
  const index = new Map(list.map((p, i) => [p.uid, i]));
  const request = {
    estate: estateInput.value,
    persons: list.map(p => {
      const dead = CAN_BE_REPRESENTED.includes(p.relation) && p.predeceased;
      return {
        name: p.rawName,
        relation: p.relation,
        alive: !dead,
        via: PARENT_RELATIONS[p.relation] && index.has(p.via) ? index.get(p.via) : null,
        line: NEEDS_LINE.includes(p.relation) && p.line ? p.line : null,
        commonChild: hasSpouse && p.relation === "CHILD" && p.common,
        disabled: !NO_TAX_QUESTIONS.includes(p.relation) && !dead && p.disabled,
        siblingExemption: p.relation === "SIBLING" && !dead && p.exempt
      };
    }),
    spouseOption: !spouseSection.hidden ? form.elements.option.value : null,
    spouseAge: !ageBlock.hidden ? Number(ageInput.value) : null
  };

  const button = document.getElementById("submit");
  button.disabled = true;
  try {
    const response = await fetch("api/succession", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(request)
    });
    const body = await response.json();
    if (body.status === "ok") {
      showResult(body, Number(estateInput.value));
    } else {
      showProblems([{ text: body.message || "The computation failed." }]);
    }
  } catch (error) {
    showProblems([{ text: "The server could not be reached." }]);
  } finally {
    button.disabled = false;
  }
}

// --- wiring -------------------------------------------------------------------

EXAMPLES.forEach((example, i) => exampleSelect.add(new Option(example.label, String(i))));
exampleSelect.addEventListener("change", () => {
  if (exampleSelect.value !== "") loadExample(EXAMPLES[Number(exampleSelect.value)]);
  exampleSelect.value = "";
});
document.getElementById("reset").addEventListener("click", () => {
  clearForm();
  addPerson({ relation: "SPOUSE" });
  addPerson({ relation: "CHILD" });
  refresh();
  estateInput.focus();
});
document.getElementById("add").addEventListener("click", () => {
  const row = addPerson();
  refresh();
  row.querySelector(".name").focus();
});
form.addEventListener("change", refresh);
form.addEventListener("input", event => {
  if (event.target.hasAttribute("aria-invalid")) event.target.removeAttribute("aria-invalid");
});
form.addEventListener("submit", submit);

addPerson({ relation: "SPOUSE" });
addPerson({ relation: "CHILD" });
refresh();
