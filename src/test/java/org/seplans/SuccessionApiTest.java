package org.seplans;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.SpringBootTest.WebEnvironment;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/** End to end: HTTP request, Spring, the real swipl process, and back. */
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
class SuccessionApiTest {

	@Value("${local.server.port}")
	int port;

	@Autowired
	JsonMapper json;

	private final HttpClient client = HttpClient.newHttpClient();

	private HttpResponse<String> post(String body) throws Exception {
		HttpRequest request = HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api/succession"))
				.header("Content-Type", "application/json").POST(HttpRequest.BodyPublishers.ofString(body)).build();
		return client.send(request, HttpResponse.BodyHandlers.ofString());
	}

	@Test
	void spouseUsufructWithCommonChildren() throws Exception {
		HttpResponse<String> response = post("""
				{"estate": 600000, "spouseAge": 65, "spouseOption": "USUFRUCT", "persons": [
				  {"name": "Claire", "relation": "SPOUSE"},
				  {"name": "Luc", "relation": "CHILD", "commonChild": true},
				  {"name": "Emma", "relation": "CHILD", "commonChild": true}]}
				""");
		assertEquals(200, response.statusCode(), response.body());
		JsonNode body = json.readTree(response.body());
		assertEquals("ok", body.get("status").asString());

		JsonNode spouse = body.get("heirs").get(0);
		assertEquals("Claire", spouse.get("name").asString());
		assertEquals("usufruct", spouse.get("right").asString());
		assertEquals(0, spouse.get("value").decimalValue().compareTo(new java.math.BigDecimal("240000")));
		assertEquals(0, spouse.get("tax").decimalValue().signum());

		JsonNode child = body.get("heirs").get(1);
		assertEquals("Luc", child.get("name").asString());
		assertEquals("bare", child.get("right").asString());
		assertEquals("1/2", child.get("fraction").asString());
		assertEquals(0, child.get("value").decimalValue().compareTo(new java.math.BigDecimal("180000")));
		assertEquals(0, child.get("tax").decimalValue().compareTo(new java.math.BigDecimal("14194.35")));
	}

	@Test
	void childrenExcludeParents() throws Exception {
		HttpResponse<String> response = post("""
				{"estate": 100000.50, "persons": [
				  {"name": "Luc", "relation": "CHILD"},
				  {"name": "Jeanne", "relation": "MOTHER"}]}
				""");
		assertEquals(200, response.statusCode(), response.body());
		JsonNode heirs = json.readTree(response.body()).get("heirs");
		assertTrue(heirs.get(0).get("heir").asBoolean());
		assertEquals(0, heirs.get(0).get("tax").decimalValue().compareTo(new java.math.BigDecimal("0.03")));
		assertFalse(heirs.get(1).get("heir").asBoolean());
		assertTrue(heirs.get(1).get("value").isNull());
	}

	@Test
	void missingOptionIsRejectedWithAMessage() throws Exception {
		HttpResponse<String> response = post("""
				{"estate": 600000, "persons": [
				  {"relation": "SPOUSE"}, {"relation": "CHILD", "commonChild": true}]}
				""");
		assertEquals(400, response.statusCode(), response.body());
		JsonNode body = json.readTree(response.body());
		assertEquals("invalid", body.get("status").asString());
		assertTrue(body.get("message").asString().contains("option"));
	}

	@Test
	void grandchildrenRepresentAPredeceasedChild() throws Exception {
		HttpResponse<String> response = post("""
				{"estate": 600000, "persons": [
				  {"name": "Luc", "relation": "CHILD"},
				  {"name": "Anne", "relation": "CHILD", "alive": false},
				  {"name": "Zoe", "relation": "DESCENDANT", "via": 1},
				  {"name": "Tom", "relation": "DESCENDANT", "via": 1}]}
				""");
		assertEquals(200, response.statusCode(), response.body());
		JsonNode heirs = json.readTree(response.body()).get("heirs");
		assertEquals("1/2", heirs.get(0).get("fraction").asString());
		assertFalse(heirs.get(1).get("heir").asBoolean());
		assertEquals("1/4", heirs.get(2).get("fraction").asString());
		assertEquals(0, heirs.get(2).get("allowance").decimalValue().compareTo(new java.math.BigDecimal("50000")));
		assertEquals(0, heirs.get(3).get("tax").decimalValue().compareTo(new java.math.BigDecimal("18194.35")));
	}

	@Test
	void collateralsSplitBetweenLinesWithTaxPending() throws Exception {
		HttpResponse<String> response = post("""
				{"estate": 400000, "persons": [
				  {"name": "Paul", "relation": "UNCLE_AUNT", "line": "PATERNAL"},
				  {"name": "Lea", "relation": "FIRST_COUSIN", "line": "MATERNAL"},
				  {"name": "Max", "relation": "PACS_PARTNER"}]}
				""");
		assertEquals(200, response.statusCode(), response.body());
		JsonNode heirs = json.readTree(response.body()).get("heirs");
		assertEquals("1/2", heirs.get(0).get("fraction").asString());
		assertEquals("pending", heirs.get(0).get("taxStatus").asString());
		assertTrue(heirs.get(0).get("tax").isNull());
		assertEquals("1/2", heirs.get(1).get("fraction").asString());
		assertFalse(heirs.get(2).get("heir").asBoolean());
	}

	@Test
	void estateWithoutHeirIsReported() throws Exception {
		HttpResponse<String> response = post("""
				{"estate": 400000, "persons": [{"name": "Max", "relation": "COHABITANT"}]}
				""");
		assertEquals(200, response.statusCode(), response.body());
		JsonNode body = json.readTree(response.body());
		assertEquals("ok", body.get("status").asString());
		assertTrue(body.get("message").asString().contains("State"));
	}

	@Test
	void validationMessagesUseTheNamesTyped() throws Exception {
		HttpResponse<String> response = post("""
				{"estate": 400000, "persons": [
				  {"name": "Luc", "relation": "CHILD"},
				  {"name": "Zoe", "relation": "DESCENDANT"},
				  {"relation": "UNCLE_AUNT"}]}
				""");
		assertEquals(400, response.statusCode(), response.body());
		assertTrue(json.readTree(response.body()).get("message").asString().startsWith("Zoe:"), response.body());

		response = post("""
				{"estate": 400000, "persons": [{"relation": "UNCLE_AUNT"}]}
				""");
		assertEquals(400, response.statusCode(), response.body());
		assertTrue(json.readTree(response.body()).get("message").asString().startsWith("Person 1:"), response.body());

		response = post("""
				{"estate": 400000, "persons": [{"relation": "DESCENDANT", "via": 7}]}
				""");
		assertEquals(400, response.statusCode(), response.body());
	}

	@Test
	void malformedRequestIsRejected() throws Exception {
		assertEquals(400, post("{\"estate\": \"abc\"}").statusCode());
		assertEquals(400, post("{\"estate\": 1000, \"persons\": [{\"relation\": \"COUSIN\"}]}").statusCode());
		assertEquals(400, post("{\"estate\": -5, \"persons\": [{\"relation\": \"CHILD\"}]}").statusCode());
	}
}
