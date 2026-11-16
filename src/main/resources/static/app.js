"use strict";

const RELATIONS = { SPOUSE: "Spouse", CHILD: "Child", FATHER: "Father", MOTHER: "Mother" };
const RIGHTS = { full: "Full ownership", usufruct: "Usufruct", bare: "Bare ownership" };

const form = document.getElementById("form");
const personsBody = document.querySelector("#persons tbody");
const spouseSection = document.getElementById("spouse-section");
const optionBlock = document.getElementById("option-block");
const ageBlock = document.getElementById("age-block");
const message = document.getElementById("message");
const result = document.getElementById("result");
const euro = new Intl.NumberFormat("en-IE", { style: "currency", currency: "EUR" });

function addPerson(relation = "CHILD", name = "") {
  const row = document.createElement("tr");

  const nameInput = document.createElement("input");
  nameInput.type = "text";
  nameInput.className = "name";
  nameInput.value = name;
  nameInput.setAttribute("aria-label", "Name");

  const select = document.createElement("select");
  select.className = "relation";
  select.setAttribute("aria-label", "Relationship");
  for (const [value, label] of Object.entries(RELATIONS)) {
    select.add(new Option(label, value, false, value === relation));
  }

  const common = document.createElement("input");
  common.type = "checkbox";
  common.className = "common";
  common.checked = true;
  common.setAttribute("aria-label", "Also the spouse's child");

  const remove = document.createElement("button");
  remove.type = "button";
  remove.className = "remove";
  remove.textContent = "Remove";
  remove.addEventListener("click", () => { row.remove(); refresh(); });

  for (const element of [nameInput, select, common, remove]) {
    row.insertCell().append(element);
  }
  select.addEventListener("change", refresh);
  common.addEventListener("change", refresh);
  personsBody.append(row);
  refresh();
}

function persons() {
  return [...personsBody.rows].map(row => ({
    name: row.querySelector(".name").value,
    relation: row.querySelector(".relation").value,
    commonChild: row.querySelector(".common").checked
  }));
}

/** Shows only the questions that matter for the family currently listed. */
function refresh() {
  const list = persons();
  const hasSpouse = list.some(p => p.relation === "SPOUSE");
  const children = list.filter(p => p.relation === "CHILD");
  const allCommon = children.length > 0 && children.every(p => p.commonChild);

  for (const row of personsBody.rows) {
    const isChild = row.querySelector(".relation").value === "CHILD";
    row.querySelector(".common").hidden = !(isChild && hasSpouse);
  }

  const optionApplies = hasSpouse && allCommon;
  const usufruct = optionApplies && form.elements.option.value === "USUFRUCT";
  spouseSection.hidden = !optionApplies;
  optionBlock.hidden = !optionApplies;
  ageBlock.hidden = !usufruct;
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
  for (const heir of heirs) {
    const row = body.insertRow();
    cell(row, heir.name);
    cell(row, RELATIONS[heir.relation]);
    if (heir.heir) {
      cell(row, RIGHTS[heir.right]);
      cell(row, heir.fraction, true);
      cell(row, money(heir.value), true);
      cell(row, heir.allowance === null ? "Exempt" : money(heir.allowance), true);
      cell(row, money(heir.taxable), true);
      cell(row, money(heir.tax), true);
      cell(row, money(heir.net), true);
      totalTax += heir.tax;
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
  label.textContent = "Total tax";
  cell(total, money(totalTax), true);
  total.insertCell();

  document.getElementById("valuation-note").hidden = !split;
  result.hidden = false;
}

async function submit(event) {
  event.preventDefault();
  message.hidden = true;
  result.hidden = true;

  const list = persons();
  const hasSpouse = list.some(p => p.relation === "SPOUSE");
  const optionVisible = !spouseSection.hidden;
  const age = document.getElementById("spouse-age").value;
  const request = {
    estate: document.getElementById("estate").value || null,
    persons: list.map(p => ({ ...p, commonChild: hasSpouse && p.relation === "CHILD" && p.commonChild })),
    spouseOption: optionVisible && form.elements.option.value ? form.elements.option.value : null,
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
