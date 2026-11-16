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
const NEEDS_LINE = ["GRANDPARENT", "GREAT_GRANDPARENT", "UNCLE_AUNT", "GREAT_UNCLE_AUNT",
  "FIRST_COUSIN", "COLLATERAL_5", "COLLATERAL_6"];

const form = document.getElementById("form");
const personsBody = document.querySelector("#persons tbody");
const spouseSection = document.getElementById("spouse-section");
const ageBlock = document.getElementById("age-block");
const message = document.getElementById("message");
const result = document.getElementById("result");
const euro = new Intl.NumberFormat("en-IE", { style: "currency", currency: "EUR" });

let nextUid = 1;

function labelled(text, control, before) {
  const label = document.createElement("label");
  if (before) label.append(text, control); else label.append(control, " " + text);
  return label;
}

function addPerson(relation = "CHILD", name = "") {
  const row = document.createElement("tr");
  row.dataset.uid = String(nextUid++);

  const nameInput = document.createElement("input");
  nameInput.type = "text";
  nameInput.className = "name";
  nameInput.value = name;
  nameInput.setAttribute("aria-label", "Name");

  const select = document.createElement("select");
  select.className = "relation";
  select.setAttribute("aria-label", "Relationship");
  for (const [group, relations] of RELATION_GROUPS) {
    const optgroup = document.createElement("optgroup");
    optgroup.label = group;
    for (const [value, label] of Object.entries(relations)) {
      optgroup.append(new Option(label, value, false, value === relation));
    }
    select.append(optgroup);
  }

  const predeceased = document.createElement("input");
  predeceased.type = "checkbox";
  predeceased.className = "predeceased";

  const via = document.createElement("select");
  via.className = "via";

  const line = document.createElement("select");
  line.className = "line";
  line.add(new Option("Choose…", ""));
  line.add(new Option("Father's side", "PATERNAL"));
  line.add(new Option("Mother's side", "MATERNAL"));

  const common = document.createElement("input");
  common.type = "checkbox";
  common.className = "common";
  common.checked = true;

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
    none);
  row.insertCell().append(remove);

  nameInput.addEventListener("input", refresh);
  personsBody.append(row);
  refresh();
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
    common: row.querySelector(".common").checked
  }));
}

/** Shows only the questions that matter for the family currently listed. */
function refresh() {
  const list = rows();
  const hasSpouse = list.some(p => p.relation === "SPOUSE");

  for (const person of list) {
    const { row, relation } = person;
    const parents = PARENT_RELATIONS[relation];
    const show = {
      via: Boolean(parents),
      line: NEEDS_LINE.includes(relation),
      predeceased: CAN_BE_REPRESENTED.includes(relation),
      common: relation === "CHILD" && hasSpouse
    };

    // Rebuild the list of possible parents, keeping the current choice if still valid.
    const via = row.querySelector(".via");
    const candidates = parents ? list.filter(p => p.uid !== person.uid && parents.includes(p.relation)) : [];
    via.replaceChildren(new Option(candidates.length ? "Choose…" : "Add the parent first", ""));
    for (const candidate of candidates) {
      via.add(new Option(candidate.name, candidate.uid, false, candidate.uid === person.via));
    }

    for (const [name, visible] of Object.entries(show)) {
      row.querySelector("." + name).closest("label").hidden = !visible;
    }
    row.querySelector(".none").hidden = Object.values(show).some(Boolean);
  }

  // The spouse's option exists when every child who inherits or is represented is common.
  const represented = new Set(list.map(p => p.via).filter(Boolean));
  const stems = list.filter(p => p.relation === "CHILD" && (!p.predeceased || represented.has(p.uid)));
  const optionApplies = hasSpouse && stems.length > 0 && stems.every(p => p.common);
  spouseSection.hidden = !optionApplies;
  ageBlock.hidden = !(optionApplies && form.elements.option.value === "USUFRUCT");
}

function showMessage(text, kind) {
  message.textContent = text;
  message.className = kind;
  message.hidden = false;
}

function money(value) {
  return value === null || value === undefined ? "—" : euro.format(value);
}

function cell(row, text, numeric) {
  const td = row.insertCell();
  td.textContent = text;
  if (numeric) td.className = "num";
  return td;
}

function showResult(heirs) {
  const body = document.querySelector("#heirs tbody");
  const foot = document.querySelector("#heirs tfoot");
  const reasons = document.getElementById("reasons");
  body.replaceChildren();
  foot.replaceChildren();
  reasons.replaceChildren();

  let totalTax = 0;
  let split = false;
  let pending = false;
  for (const heir of heirs) {
    const row = body.insertRow();
    cell(row, heir.name);
    cell(row, RELATIONS[heir.relation]);
    if (heir.heir) {
      cell(row, RIGHTS[heir.right]);
      cell(row, heir.fraction, true);
      cell(row, money(heir.value), true);
      if (heir.taxStatus === "pending") {
        cell(row, "Not computed yet", true).colSpan = 4;
        pending = true;
      } else {
        cell(row, heir.taxStatus === "exempt" ? "Exempt" : money(heir.allowance), true);
        cell(row, money(heir.taxable), true);
        cell(row, money(heir.tax), true);
        cell(row, money(heir.net), true);
        totalTax += heir.tax;
      }
      split = split || heir.right !== "full";
    } else {
      row.className = "not-heir";
      cell(row, "Not an heir");
      for (let i = 0; i < 6; i++) cell(row, "—", true);
    }
    const reason = document.createElement("li");
    const who = document.createElement("strong");
    who.textContent = heir.name + ": ";
    reason.append(who, [heir.basis, heir.taxBasis].filter(Boolean).join(" "));
    reasons.append(reason);
  }

  const total = foot.insertRow();
  const label = total.insertCell();
  label.colSpan = 7;
  label.textContent = pending ? "Total tax computed so far" : "Total tax";
  cell(total, money(totalTax), true);
  total.insertCell();

  document.getElementById("valuation-note").hidden = !split;
  document.getElementById("pending-note").hidden = !pending;
  result.hidden = false;
}

async function submit(event) {
  event.preventDefault();
  message.hidden = true;
  result.hidden = true;

  const list = rows();
  const hasSpouse = list.some(p => p.relation === "SPOUSE");
  const index = new Map(list.map((p, i) => [p.uid, i]));
  const option = form.elements.option.value;
  const age = document.getElementById("spouse-age").value;
  const request = {
    estate: document.getElementById("estate").value || null,
    persons: list.map(p => ({
      name: p.rawName,
      relation: p.relation,
      alive: !(CAN_BE_REPRESENTED.includes(p.relation) && p.predeceased),
      via: PARENT_RELATIONS[p.relation] && index.has(p.via) ? index.get(p.via) : null,
      line: NEEDS_LINE.includes(p.relation) && p.line ? p.line : null,
      commonChild: hasSpouse && p.relation === "CHILD" && p.common
    })),
    spouseOption: !spouseSection.hidden && option ? option : null,
    spouseAge: !ageBlock.hidden && age !== "" ? Number(age) : null
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
      if (body.message) showMessage(body.message, "info");
      showResult(body.heirs);
    } else {
      showMessage(body.message || "The computation failed.", body.status === "unsupported" ? "info" : "error");
    }
  } catch (error) {
    showMessage("The server could not be reached.", "error");
  } finally {
    button.disabled = false;
  }
}

document.getElementById("add").addEventListener("click", () => addPerson());
form.addEventListener("change", refresh);
form.addEventListener("submit", submit);

addPerson("SPOUSE");
addPerson("CHILD");
