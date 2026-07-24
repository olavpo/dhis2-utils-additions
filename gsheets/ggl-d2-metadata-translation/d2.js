var auth;

/** MAIN FUNCTIONS **/
function performAction() {
	var action = getAction();
	
	//NULL = need to configure
	
	if (action == 0) dialogInfo("Connected to " + getUrl());
	else if (action == 1) writeSchema();
	else if (action == 2) populateSpreadsheet();
	else if (action == 3) populatePending();
	else if (action == 4) populateDHIS2();
}

function populateSpreadsheet() {  
	if (!dialogWarning("This will overwrite any changes. Continue?")) return;
  
	var resc = resources();
	for (var i = 0; i < resc.length; i++) {
		if (resc[i].fields != "") {
			var data = d2FetchResource(resc[i].resource, resc[i].fields + ",translations,id", resc[i].filter); 
			writeResourceSheet(resc[i].resource, resc[i].fields, resc[i].keys, data);
		}
	}
   
	resizeSheets();
	dialogInfo("Done fetching metadata for translation.");
}

function populatePending() {
	if (!dialogWarning("This will overwrite the current list of translations waiting to uploaded. Continue?")) return;
  
	resetPending();
  
	var resc = resources();
	for (var i = 0; i < resc.length; i++) {
		writePending(resc[i].resource);
	}
  
	resizeSheets("Pending");
	dialogInfo("Done preparing translations for upload. Note: ALL translations will be uploaded, not only those changed in this document.");
}

function populateDHIS2() {
	if (!dialogWarning("This will modify DHIS2 (" + getUrl() + "), overwriting ANY translations with those provided here. Continue?")) return;
  
	//One row at the time..
	var sheet = utilGetSheet("Pending", false);
	for (var rowI = 3; rowI <= sheet.getLastRow(); rowI++) {
		var toDo = (sheet.getRange(rowI, 4).getValue() == "");
		if (toDo) {
      
			var nextRow = sheet.getLastRow() + 1;
			var data = sheet.getRange(rowI, 1, 1, 3).getValues();
			var result = d2UpdateTranslation(data[0][0], data[0][1], data[0][2]);
			sheet.getRange(rowI, 4, 1, 3).setValues([[result.statusCode, result.message, utilTimeStamp()]]).setNumberFormat("@");
		}
	}
 
	resizeSheets("Pending");
	dialogInfo("Done uploading translation to " + getUrl());
}


/** POPULATE MAIN SHEETS **/
function writeResourceSheet(resource, fields, fieldKeys, data) {
	var sheet = utilGetSheet(resource, true);
	sheet.setTabColor("green");
  
	var loc = locales();
	fieldKeys = fieldKeys.split(",");
	fields = fields.split(",");
  
  
	//Remove existing protections
	var protections = sheet.getProtections(SpreadsheetApp.ProtectionType.RANGE);
	for (var i = 0; i < protections.length; i++) {
		var protection = protections[i];
		if (protection.canEdit()) {
			protection.remove();
		}
	}
  
	//figure out how many locales we have - need to also include locales that have translations, to make sure they're not lost when updating again
	for (var i = 0; i < data.length; i++) {
		if (data[i].hasOwnProperty("translations")) {
			for (var j = 0; j < data[i].translations.length; j++) {
				loc.push(data[i].translations[j]["locale"]);
			}
		}
	}
	var uniqueLoc = {};
	for (var i = 0; i < loc.length; i++) {
		uniqueLoc[loc[i]] = true; 
	}
  
	//Write headers
	var fieldHeader = ["id"], localeHeader = [""];
	for (var j = 0; j < fields.length; j++) {
		fieldHeader.push(fields[j]);
		localeHeader.push("");
	}
	for (var loc in uniqueLoc) {
		for (var j = 0; j < fields.length; j++) {
			fieldHeader.push(fieldKeys[j]);
			localeHeader.push(loc);
		}
	}
  
	sheet.getRange(2,1, 2, fieldHeader.length).setValues([localeHeader, fieldHeader]);
  
	var field, val, values = [];
	for (var i = 0; i < data.length; i++) {
		var rowValues = [];
		rowValues.push(data[i].id);
    
		//Get all "original" props
		for (var j = 0; j < fields.length; j++) {
			val = data[i].hasOwnProperty(fields[j]) ? data[i][fields[j]] : "";
			rowValues.push(val);
		}
    
		//Then get current values for each locale and each property (in order)
		for (var loc in uniqueLoc) {
			for (var j = 0; j < fields.length; j++) {
				if (data[i].hasOwnProperty("translations")) {
					var found = false;
					for (var k = 0; k < data[i].translations.length && !found; k++) {
						if (data[i].translations[k].locale == loc && data[i].translations[k].property == fieldKeys[j]) {
							found = true;
							rowValues.push(data[i].translations[k].value);
						}
					}
					if (!found) rowValues.push("");
				}
				else {
					rowValues.push("");
				}
			}
		}
		values.push(rowValues);
	}
	if (values.length > 0 && values[0].length > 0) sheet.getRange(4,1, values.length, values[0].length).setValues(values).setNumberFormat("@");
    
	//Headings
	sheet.getRange(1,1).setValue(resource);
	sheet.getRange(1,2).setValue(utilTimeStamp());
    
	//protect first three rows (headers) and first X columns
	sheet.getRange(1, 1, 3, sheet.getLastColumn()).protect().setDescription("Headers not editable");
	sheet.getRange(4, 1, sheet.getLastRow(), 1+fields.length).protect().setDescription("Original not editable");
}

function writePending(resource) {
	var sheet = utilGetSheet(resource, false);
  
	var data = sheet.getRange(2,1,sheet.getLastRow()-1, sheet.getLastColumn()).getValues();
    
	//iterate local row until hitting something
	var locales = data[0];
	var fieldKeys = data[1];
  
	//Find what row the translations start at
	var startCol, totalCol = locales.length;
	for (var i = 0; i < locales.length; i++) {
		if (locales[i].length == 2) {
			startCol = i; 
			break; 
		}
	}
  
	var translationUpdates = [];
	for (var i = 2; i < data.length; i++) {
		var translationUpdate = {
			"id": data[i][0],
			"translations": []
		};
		for (var j = startCol; j < totalCol; j++) {
			if (data[i][j] != "" && locales[j] != "" && fieldKeys[j] != "") {
				translationUpdate.translations.push({
					"locale": locales[j],
					"property": fieldKeys[j],
					"value": data[i][j]
				});
			}
		}
		translationUpdates.push(translationUpdate);
	}
  
  
	var rows = [];
	for (var i = 0; i < translationUpdates.length; i++) {
		rows.push([resource, translationUpdates[i].id, JSON.stringify({"translations": translationUpdates[i].translations})]);
	}
	var pendingSheet = utilGetSheet("Pending", false);
	pendingSheet.getRange((1+pendingSheet.getLastRow()), 1, rows.length, 3).setValues(rows).setNumberFormat("@");

}

function writeSettings(systemInfo) {
	var sheet = utilGetSheet("Settings", false);
	sheet.getRange(1,1).setValue(["Instance"]);
	sheet.getRange(1,2).setValue([systemInfo.systemName]);
	sheet.getRange(2,1).setValue(["Version"]);  
	sheet.getRange(2,2).setValue([systemInfo.version]);  
	sheet.getRange(3,1).setValue(["URL"]);  
	sheet.getRange(3,2).setValue([getUrl()]);  
	sheet.getRange(4,1).setValue(["Locales"]);  
	sheet.getRange(4,3).setValue(["Comma-separated two-character locales, e.g. \"fr,es\""]);  
  
	sheet.getRange(1, 1, 3, sheet.getLastColumn()).protect().setDescription("Headers not editable");
	sheet.getRange(5, 1, 2, 1).protect().setDescription("Headers not editable");
	sheet.getRange(5, 1, 2, 1).protect().setDescription("Headers not editable");
  
	resizeSheets("Settings");
}

function writeSchema() {
	//Make headings
	var sheet = utilGetSheet("Settings", false);
	sheet.getRange(8, 1).setValue(["resource"]);
	sheet.getRange(8, 2).setValue(["translatableFields"]);
	sheet.getRange(8, 3).setValue(["translatableFieldKeys"]);
	sheet.getRange(8, 4).setValue(["filter"]);
	sheet.getRange(8, 5).setValue(["Include (yes)"]);
  
	//Get schema
	var schema, schemas = d2SchemaTranslatable();

  
	schemas = schemas.sort(function(a, b) {
		return a.plural.localeCompare(b.plural);
	});
  
	var row = 9;
	for (var i = 0; i < schemas.length; i++) {
		schema = schemas[i];
		if (schema.translatable) {
			var fields = [], fieldKeys = [], prop;
			for (var j = 0; j < schema.properties.length; j++) {
				prop = schema.properties[j];
				if (prop.hasOwnProperty("translationKey")) {
					fields.push(prop.name);
					fieldKeys.push(prop.translationKey);
				}
			}
      
			var sorted = utilFieldSort(fields, fieldKeys);
      
			sheet.getRange(row, 1).setValue([schema.plural]);
			sheet.getRange(row, 2).setValue([sorted.fields.join(",")]);
			sheet.getRange(row, 3).setValue([sorted.fieldKeys.join(",")]);
			row += 1;
		}
	}
  
	resizeSheets("Settings");
	dialogInfo("Loaded schema, choose objects to translate");
}


/** INTERACTION WITH DHIS2 **/
function d2SystemInfo(baseUrl, user, password) {  
	var headers = {
		"Authorization" : "Basic " + Utilities.base64Encode(user + ":" + password)
	};
	var params = {
		"method":"GET",
		"headers":headers
	};
  
	var url = baseUrl + "/api/system/info.json";
  
	var response = UrlFetchApp.fetch(url, params);
  
	return JSON.parse(response.getContentText());
}

function d2SchemaTranslatable() {  
	var headers = {
		"Authorization" : "Basic " + getAuth()
	};
	var params = {
		"method":"GET",
		"headers":headers
	};
  
	var url = getUrl() + "/api/schemas.json";
  
	var response = UrlFetchApp.fetch(url, params);
  
	return JSON.parse(response.getContentText())["schemas"];
}

function d2FetchResource(resource, fields, filter, paging) {  
	var headers = {
		"Authorization" : "Basic " + getAuth()
	};
	var params = {
		"method":"GET",
		"headers":headers
	};
  
	//fields default to owner
	if (!fields) fields = ":owner";
  
	var url = getUrl() + "/api/" + resource + ".json";
	url += "?fields=" + fields;
	if (filter) url += "&filter=" + filter;
	if (!paging) url += "&paging=false";
  
	var response = UrlFetchApp.fetch(url, params);
	var data = JSON.parse(response.getContentText())[resource];
  
	return data;
}

function d2UpdateResource(resource, id, property, value) {  
	var headers = {
		"Authorization" : "Basic " + getAuth()
	};
  
	var payload = {};
	payload[property] = value;
  
	var params = {
		"method": "PATCH",
		"payload": JSON.stringify(payload),
		"contentType": "application/json; charset=utf-8",
		"headers": headers,
		"muteHttpExceptions": true
	};

	var url = getUrl() + "/api/" + resource + "/" + id + "/" + property;
    
	var response = UrlFetchApp.fetch(url, params);
	return {"statusCode": response.getResponseCode(), "message": response.getContentText()};
}

function d2UpdateTranslation(resource, id, payload) {  
	var headers = {
		"Authorization" : "Basic " + getAuth()
	};
  
	var params = {
		"method": "PUT",
		"payload": payload,
		"contentType": "application/json; charset=utf-8",
		"headers": headers,
		"muteHttpExceptions": true
	};

	var url = getUrl() + "/api/" + resource + "/" + id + "/translations";
    
	var response = UrlFetchApp.fetch(url, params);
	Logger.log(response);
	return {"statusCode": response.getResponseCode(), "message": response.getContentText()};
}


/** STRUCUTRE AND FORMATTING **/
function resizeSheets(sheetName) {
  
	var sheets = [];
	if (sheetName) {
		sheets = [utilGetSheet(sheetName, false)];
	}
	else {
		sheets = SpreadsheetApp.getActiveSpreadsheet().getSheets();
	}
  
	for (var i = 0; i < sheets.length; i++) {

		for (var j = 1; j <= sheets[i].getLastColumn(); j++) {
			sheets[i].autoResizeColumn(j);
			if (sheets[i].getColumnWidth(j) > 500) sheets[i].setColumnWidth(j, 500);
		}
	}
  
}

function resetReview() {
	var reviewSheet = utilGetSheet("Review", true);
	reviewSheet.getRange(1, 1, 1, 2).setValues([["Review", utilTimeStamp()]]);
	reviewSheet.getRange(2, 1, 1, 7).setValues([["Resources", "id", "name", "Property", "Current", "Proposed", "Accept (yes)"]]);
}

function resetPending() {
	var pendingSheet = utilGetSheet("Pending", true);
	pendingSheet.getRange(1, 1, 1, 2).setValues([["Pending", utilTimeStamp()]]);
	pendingSheet.getRange(2, 1, 1, 9).setValues([["Resources", "id", "name", "Property", "Current", "Proposed", "Status", "Error", "Date"]]);
}

function resetLog() {
	var logSheet = utilGetSheet("Changelog", false);
	logSheet.getRange(1, 1, 1, 2).setValues([["Pending", utilTimeStamp()]]);
	logSheet.getRange(2, 1, 1, 7).setValues([["Resources", "id", "name", "Property", "Previous", "Current", "Date"]]);
}

//Remove any translatable resources NOT included
function resetResources() {
	var sheets = SpreadsheetApp.getActiveSpreadsheet().getSheets();
	var settingsSheet = utilGetSheet("Settings", false);
	for (var i = 9; i <= settingsSheet.getLastRow(); i++) {
		if (settingsSheet.getRange(i, 5).getValue() != "yes") {
			var sheet = false;
			var rescName = settingsSheet.getRange(i, 1).getValue();
			for (var j = 0; j < sheets.length && !sheet; j++) {
				if (sheets[j].getName() == rescName) sheet = sheets[j];
			}
			if (sheet) SpreadsheetApp.getActive().deleteSheet(sheet);
		}
	}
}


/** UTILITIES **/
function utilArrayIdDict(array) {
  
	var dict = {};
	for (var i = 0; i < array.length; i++) {
		dict[array[i].id] = array[i]; 
	}
  
	return dict;
}

//data: array of json objects
//returns: unique properties of all objects
function utilResourceProperties(data) {
	var allHeaders = {}, headers = ["id"];

	var i = 1;
	for (var j = 0; j < data.length; j++) {
		for (var key in data[j]) {
			allHeaders[key] = true;
		}
	}
	for (var key in allHeaders) {
		if (key != "id") headers.push(key);
	}
  
	return headers;
}

//returns a sheet with the name of the given resource, or create
function utilGetSheet(name, empty) {
	var sheets = SpreadsheetApp.getActiveSpreadsheet().getSheets();
	var sheet = false;

	for (var i = 0; i < sheets.length && !sheet; i++) {
		if (sheets[i].getName() == name) sheet = sheets[i];
	}
	if (!sheet) sheet = SpreadsheetApp.getActiveSpreadsheet().insertSheet(name);
	else if (empty) {
		sheet.clear();
	}
	return sheet;
}

function utilFieldSort(fields, fieldKeys) {
	//hacky sort via object
	var sorted = {};
	var sortedKeys = {};
  
	//name
	for (var i = 0; i < fields.length; i++) {
		if (fields[i] == "name") {
			sorted[fields[i]] = true;
			sortedKeys[fieldKeys[i]] = true;
			break; 
		}
	}
  
	//shortName
	for (var i = 0; i < fields.length; i++) {
		if (fields[i] == "shortName") {
			sorted[fields[i]] = true;
			sortedKeys[fieldKeys[i]] = true;
			break; 
		}
	}
  
  
	//description
	for (var i = 0; i < fields.length; i++) {
		if (fields[i] == "description") {
			sorted[fields[i]] = true;
			sortedKeys[fieldKeys[i]] = true;
			break; 
		}
	}
  
  
	//everything else
	for (var i = 0; i < fields.length; i++) {
		if (!sorted[fields[i]]) {
			sorted[fields[i]] = true;
			sortedKeys[fieldKeys[i]] = true;
		}
	}
  
	fields = [];
	for (var f in sorted) {
		fields.push(f);
	}
  
	fieldKeys = [];
	for (var k in sortedKeys) {
		fieldKeys.push(k);
	}
  
	Logger.log(fields);
	Logger.log(fieldKeys);
  
	return {"fields": fields, "fieldKeys": fieldKeys};
  
}

function utilTimeStamp() {
	return new Date().toISOString().substring(0, 16); 
}


/** GUI **/
function onInstall(e) {
	onOpen();
}

function onOpen() {

	SpreadsheetApp.getUi() // Or DocumentApp or FormApp.
		.createMenu("DHIS2 translations")    
		.addItem("Fetch metadata with translations", "actionFetch")
		.addItem("Prepare translations for upload to DHIS2", "actionPrep")
		.addItem("Push translations to DHIS2", "populateDHIS2")
		.addSeparator()
		.addSubMenu(SpreadsheetApp.getUi().createMenu("Configuration")
			.addItem("Server connection", "actionConnection")
			.addItem("Load translatable objects", "actionDefault")
			.addSeparator()
			.addItem("Remove unused sheets (objects)", "actionResetResources")
			.addItem("Clear change log", "actionResetLog")
			.addSeparator()
			.addItem("Remove URL", "actionResetUrl")
			.addItem("Remove username", "actionResetUsername"))
		.addToUi();
}

function actionConnection() {
	connectOrAuthenticate(0);
}

function actionDefault() {
	connectOrAuthenticate(1);
}

function actionResetResources() {
	resetResources();
}

function actionResetLog() {
	resetLog();
}

function actionResetUrl() {
	deleteUrl();
}

function actionResetUsername() {
	deleteUser();
}

function actionFetch() {
	connectOrAuthenticate(2);
}

function actionPrep() {
	connectOrAuthenticate(3);
}

function actionPush() {
	connectOrAuthenticate(4);
}


function dialogUrl() {	
	var html = HtmlService.createHtmlOutputFromFile("urluserpassword")
		.setWidth(600)
		.setHeight(400);
	SpreadsheetApp.getUi() // Or DocumentApp or FormApp.
		.showModalDialog(html, "URL, username and password");
}

function dialogUser() {
	var html = HtmlService.createHtmlOutputFromFile("userpassword")
		.setWidth(600)
		.setHeight(400);
	SpreadsheetApp.getUi() // Or DocumentApp or FormApp.
		.showModalDialog(html, "Username and password");
}

function dialogPassword() {
	var html = HtmlService.createHtmlOutputFromFile("password")
		.setWidth(600)
		.setHeight(400);
	SpreadsheetApp.getUi() // Or DocumentApp or FormApp.
		.showModalDialog(html, "Password");
}

function dialogWarning(message) {
	var ui = SpreadsheetApp.getUi();
	var response = ui.alert(message, ui.ButtonSet.YES_NO);

	// Process the user's response.
	if (response == ui.Button.YES) {
		return true;
	} else {
		return false;
	}
}

function dialogInfo(message) {
	SpreadsheetApp.getUi().alert(message);
}


function receiveInfo(formData) {

	var url, user, pwd;
	if (formData.hasOwnProperty("url")) url = formData.url;
	else url = getUrl();
	
	if (formData.hasOwnProperty("username")) user = formData.username;
	else user = getUser();
	
	if (formData.hasOwnProperty("password")) pwd = formData.password;
	else pwd = false;

	var systemInfo = d2SystemInfo(url, user, pwd);
	if (systemInfo && systemInfo.hasOwnProperty("version")) {
		
		if (!hasUrl()) {
			setUrl(url);
			setUser(user);
			auth = pwd;
			writeSettings(systemInfo); 
		}
		//TODO: else if different URL
		else {
			setUrl(url);
			setUser(user);
			auth = pwd;
		}
		
		performAction();
	}
	else {
		Logger.log("Connection failed");
		Logger.log(systemInfo);
		dialogInfo("Incorrect url/username/password");

		return false;
	}
}



/** CONFIGURATION **/
function resources() {
	var sheet = utilGetSheet("Settings", false);
	var resources = [];
	for (var i = 9; i <= sheet.getLastRow(); i++) {
		if (sheet.getRange(i, 5).getValue() == "yes") {
			resources.push({
				"resource": sheet.getRange(i, 1).getValue(),
				"filter": sheet.getRange(i, 4).getValue(),
				"fields": sheet.getRange(i, 2).getValue(),
				"keys": sheet.getRange(i, 3).getValue()
			});
		}
	}
  

	return resources;
}

function locales() {
	var sheet = utilGetSheet("Settings", false);  
	return sheet.getRange(4,2).getValue().split(",");
}


/** FUNCTIONS FOR MANAGING CONNECTION TO DHIS2 **/
function connectOrAuthenticate(actionId) {

	setAction(actionId);

	if (!hasUrl()) {
		dialogUrl();
		return true;
	}
	else if (!hasUser()) {
		dialogUser();
		return true;
	} 
	else {
		dialogPassword();
		return true;
	} 
}


function setAction(action) {
	var props = PropertiesService.getDocumentProperties();
	props.setProperty("action", action);
}

function getAction() {
	var props = PropertiesService.getDocumentProperties();
	return props.getProperty("action");
}


function setUrl(url) {
	var props = PropertiesService.getDocumentProperties();
	props.setProperty("url", url);
}

function getUrl() {
	var props = PropertiesService.getDocumentProperties();
	return props.getProperty("url");
}

function deleteUrl() {
	var url = utilGetSheet("Settings", false).getRange(3,2).setValue([""]);

	var props = PropertiesService.getDocumentProperties();
	props.deleteProperty("url");
}

function hasUrl() {
	var props = PropertiesService.getDocumentProperties();
	if (props.getProperty("url") == null) return false;
	else return true;
}


function setUser(user) {
	var props = PropertiesService.getUserProperties();
	var docId = SpreadsheetApp.getActiveSpreadsheet().getUrl();
	props.setProperty(docId, user);
}

function getUser() {
	var props = PropertiesService.getUserProperties();
	var docId = SpreadsheetApp.getActiveSpreadsheet().getUrl();
	return props.getProperty(docId);
}

function deleteUser() {
	var props = PropertiesService.getUserProperties();
	var docId = SpreadsheetApp.getActiveSpreadsheet().getUrl();
	return props.deleteProperty(docId);
}

function hasUser() {
	var props = PropertiesService.getUserProperties();
	var docId = SpreadsheetApp.getActiveSpreadsheet().getUrl();
	if (props.getProperty(docId) == null) return false;
	else return true;
}


function getAuth() {
	return Utilities.base64Encode(getUser() + ":" + auth);
}
