var auth;

/** MAIN FUNCTIONS **/

function performAction() {
	var action = getAction();
	
	//NULL = need to configure
	
	if (action == 0) dialogInfo("Connected to " + getUrl());
	else if (action == 1) populateSpreadsheet();
	else if (action == 2) populateReviewSheet();
	else if (action == 3) populateDHIS2();
	else if (action == 4) writeGroupSets();
	
}


function populateSpreadsheet() {  
	if (!dialogWarning("Fetching latest metadata from " + getUrl() + ". This will overwrite any changes. Continue?")) return;
	
	var resc = resources();
	for (var i = 0; i < resc.length; i++) {
		var data = d2FetchResource(resc[i].resource, resc[i].fields, resc[i].filter);    
		writeResourceSheet(resc[i].resource, resc[i].fields, data, resc[i].editable);
	}
	
	resizeSheets();
	dialogInfo("Done fetching metadata for review.")
}


function populateReviewSheet() {
	if (!dialogWarning("This will overwrite the current content of the Review sheet. Continue?")) return;
	resetReview();
	
	var resc = resources();
	for (var i = 0; i < resc.length; i++) {
		var data = d2FetchResource(resc[i].resource, resc[i].fields, resc[i].filter);    
		reviewResourceSheet(resc[i].resource, resc[i].fields, data, resc[i].editable);
	}

	resizeSheet("Review");
	dialogInfo("Done updating review sheet.")
}


function populateDHIS2() {
	if (!dialogWarning("This will modify DHIS2 (" + getUrl() + ") with the accepted changes from the Review sheet. Continue?")) return;
	
	
	writePendingSheet();
	writePendingDHIS2();
	writeLogSheet();  
	
	resizeSheet("Pending");
	resizeSheet("Changelog");
	dialogInfo("Done uploading metadata changes.")
}


/** POPULATE MAIN SHEETS **/
//For data elements and indicators, we add the main data element groups to allow sorting
function writeGroupSets() {
	var degs = dataElementGroupSet();
	if (degs != "") {
	
		var data = d2FetchResource("dataElementGroupSets", "dataElementGroups[id,name,dataElements[id]]", "id:eq:" + degs, false);
		var groups = data[0]["dataElementGroups"];

		//Get data element sheet
		var deSheet = utilGetSheet("dataElements", false);
	
		if (deSheet.getRange(2,1).getValue() != "group") {
			deSheet.insertColumnBefore(1);
			deSheet.getRange(2,1).setValue(["group"]);
		}
	
		//move headings into the new column
		deSheet.getRange(1,1).setValue([deSheet.getRange(1,2).getValue()]);
		deSheet.getRange(1,2).setValue([deSheet.getRange(1,3).getValue()]);
		deSheet.getRange(1,3).setValue([""]);
	
		var values = [];
		for (var i = 3; i < deSheet.getLastRow()+1; i++) {
			var deId = deSheet.getRange(i,2).getValue();
			var group = "[NONE]";
			for (var j = 0; j < groups.length; j++) {
				for (var k = 0; k < groups[j].dataElements.length; k++) {
					if (groups[j].dataElements[k].id === deId) group = groups[j].name;
				}  
			}
			values.push([group]);
		}
		deSheet.getRange(3, 1, values.length).setValues(values);
		deSheet.getRange(1, 1, deSheet.getLastRow()).protect().setDescription("Group not editable");
	}
	
	var igs = indicatorGroupSet();
	if (igs != "") {
		var data = d2FetchResource("indicatorGroupSets", "indicatorGroups[id,name,indicators[id]]", "id:eq:" + igs, false);
		var groups = data[0]["indicatorGroups"];

		//Get data element sheet
		var inSheet = utilGetSheet("indicators", false);
	
		if (inSheet.getRange(2,1).getValue() != "group") {
			inSheet.insertColumnBefore(1);
			inSheet.getRange(2,1).setValue(["group"]);
		}
	
		//move headings into the new column
		inSheet.getRange(1,1).setValue([inSheet.getRange(1,2).getValue()]);
		inSheet.getRange(1,2).setValue([inSheet.getRange(1,3).getValue()]);
		inSheet.getRange(1,3).setValue([""]);
	
		var values = [];
		for (var i = 3; i < inSheet.getLastRow()+1; i++) {
			var deId = inSheet.getRange(i,2).getValue();
			var group = "[NONE]";
			for (var j = 0; j < groups.length; j++) {
				for (var k = 0; k < groups[j].indicators.length; k++) {
					if (groups[j].indicators[k].id === deId) group = groups[j].name;
				}  
			}
			values.push([group]);
		}
		inSheet.getRange(3, 1, values.length).setValues(values);
		inSheet.getRange(1, 1, inSheet.getLastRow()).protect().setDescription("Group not editable");
	}
	
	dialogInfo("Done adding group sets.")

}

function writeResourceSheet(resource, fields, data, editable) {
	var sheet = utilGetSheet(resource, true);
	sheet.setTabColor("green");
	
	//Remove existing protections
	var protections = sheet.getProtections(SpreadsheetApp.ProtectionType.RANGE);
	for (var i = 0; i < protections.length; i++) {
		var protection = protections[i];
		if (protection.canEdit()) {
			protection.remove();
		}
	}
	
	//if fields are not defined, get fields from data
	var headers;
	if (!fields) headers = utilResourceProperties(data);
	else headers = fields.split(",");
	
	for (var i = 0; i < headers.length; i++) {
		sheet.getRange(2,i+1).setValue([headers[i]]);
	}
	
	var field, val, values = [];
	for (var i = 0; i < data.length; i++) {
		var rowValues = [];
		for (var j = 0; j < headers.length; j++) {
			
			field = headers[j];
			if (field.indexOf("[") > 0) {
				field = field.split("[")[0];
				
				if (data[i][field] instanceof Array) {
					var concatenatedName = [];
					for (var k = 0; k < data[i][field].length; k++) {
						concatenatedName.push(data[i][field][k]["name"]);
					}
					val = concatenatedName.join("; ");

				}
				else {
					if (data[i].hasOwnProperty(field) && data[i][field].hasOwnProperty("name")) {
						val = data[i][field]["name"];   
					}
					else {
						val = "";
					}
				}
			}
			else {
				val = data[i][field]; 
			}
			rowValues.push((val ? val : ""));
		}
		values.push(rowValues);
	}
	if (values.length > 0 && values[0].length > 0) sheet.getRange(3,1, values.length, values[0].length).setValues(values).setNumberFormat("@");
	
	//Set background color for EDITABLE cells, else remove it
	for (var j = 0; j < headers.length; j++) {  
		if (editable && editable.indexOf(headers[j]) >= 0) {
			sheet.getRange(2,j+1, sheet.getLastRow()-1).setBackgroundColor("#98FB98");
		}
		else {
			sheet.getRange(2,j+1, sheet.getLastRow()).setBackgroundColor(null);
		}
	}
	
	//Headings
	sheet.getRange(1,1).setValue(resource);
	sheet.getRange(1,2).setValue(utilTimeStamp());
		
	//protect first two rows (headers) and first column (id)
	sheet.getRange(1, 1, 2, sheet.getLastColumn()).protect().setDescription("Headers not editable");
	sheet.getRange(1, 1, sheet.getLastRow()).protect().setDescription("ID not editable");
}

function writePendingSheet() {
	var ReviewSheet = utilGetSheet("Review", false);	
	var data = ReviewSheet.getRange(3, 1, ReviewSheet.getLastRow(), 7).getValues();
	
	var acceptedRows = [];	
	for (var rowI = 0; rowI < data.length; rowI++) {
		var accepted = (data[rowI].pop() == "yes");
		if (accepted) {
			acceptedRows.push(data[rowI]);
			
			//Delete from review sheet. Index is off by 3, since data starts on row 3
			ReviewSheet.deleteRow(rowI+3);
		}
	}
	if (acceptedRows == 0) return;
	
	var pendingSheet = utilGetSheet("Pending", false);
	pendingSheet.getRange(1 + pendingSheet.getLastRow(), 1, acceptedRows.length, 6).setValues(acceptedRows).setNumberFormat("@");
}

function writePendingDHIS2() {
	var pendingSheet = utilGetSheet("Pending", false);
	for (var rowI = 3; rowI <= pendingSheet.getLastRow(); rowI++) {

		var resource = pendingSheet.getRange(rowI, 1).getValue();
		var id = pendingSheet.getRange(rowI, 2).getValue();
		var property = pendingSheet.getRange(rowI, 4).getValue();
		var value = pendingSheet.getRange(rowI, 6).getValue();
			
		if (value == "") value = null;
		
		Logger.log(id);
			
		var response = d2UpdateResource(resource, id, property, value);
		Logger.log(response);
		pendingSheet.getRange(rowI, 7, 1, 3).setValues([[response.statusCode, response.message, utilTimeStamp()]]);
	}
}

function writeLogSheet() {
	var pendingSheet = utilGetSheet("Pending", false);
	var data = pendingSheet.getRange(3, 1, pendingSheet.getLastRow(), 9).getValues();

	var successRows = [];
	for (var rowI = 0; rowI < data.length; rowI++) {
		var statusCode = data[rowI][6];
		var success = statusCode == 200 || statusCode == 204;
		if (success) {
			successRows.push([data[rowI][0], data[rowI][1], data[rowI][2], data[rowI][3], data[rowI][4], data[rowI][5], data[rowI][8]]);
			
			//Delete from pening sheet. Index is off by 3, since data starts on row 3
			pendingSheet.deleteRow(rowI+3);
		}
	}
	
	if (successRows == 0) return;
	
	var logSheet = utilGetSheet("Changelog", false);
	logSheet.getRange(1 + logSheet.getLastRow(), 1, successRows.length, 7).setValues(successRows).setNumberFormat("@");
}

function writeSettings(systemInfo) {
	var sheet = utilGetSheet("Settings", false);
	sheet.getRange(1,1).setValue(["Instance"]);
	sheet.getRange(1,2).setValue([systemInfo.systemName]);
	sheet.getRange(2,1).setValue(["Version"]);  
	sheet.getRange(2,2).setValue([systemInfo.version]);  
	sheet.getRange(3,1).setValue(["URL"]);  
	sheet.getRange(3,2).setValue([getUrl()]);  
	sheet.getRange(5,1).setValue(["Data element group set (id)"]);  
	sheet.getRange(6,1).setValue(["Indicator group set (id)"]);  
	sheet.getRange(5,3).setValue(["A column for group will be added to data element and/or indicator sheet, with a group in the group sets. Useful for filtering/sorting the tables."]);  
	
	sheet.getRange(1, 1, 3, sheet.getLastColumn()).protect().setDescription("Headers not editable");
	sheet.getRange(5, 1, 2, 1).protect().setDescription("Headers not editable");
	sheet.getRange(5, 1, 2, 1).protect().setDescription("Headers not editable");
	
	resizeSheet("Settings");

}

/** Review AND LOGGING CHANGES **/
function reviewResourceSheet(resource, fields, data, editable) {

	if (!editable || editable.length == 0) return;
		
	var sheet = utilGetSheet(resource, false);
	var dataDict = utilArrayIdDict(data);
	var content = sheet.getRange(2,1,sheet.getLastRow()-1, sheet.getLastColumn()).getValues();
	
	//No content - just return
	if (content.length <= 1) return;
	
	//Identify column with id, name and editable properties
	var editableColumns = {}, idCol = 0, nameCol = 0;
	for (var colI = 0; colI < content[0].length; colI++) {
		var prop = content[0][colI];
		
		if (prop == "id") idCol = colI;
		if (prop == "name") nameCol = colI;
		
		if (editable.indexOf(prop) >= 0) {
			editableColumns[prop] = colI;
		}
	}
	
	//Go through all rows, comparing with what is on the server
	var id;
	var stageRows = [];
	for (var rowI = 1; rowI < content.length; rowI++) {
		var id = content[rowI][idCol];

		//for each editable property
		for (var prop in editableColumns) {
			var editedVal = content[rowI][editableColumns[prop]];
			
			var currentObject = dataDict[id];
			if (currentObject) { //check if exists on server, might have been deleted
				var name = currentObject.hasOwnProperty("name") ? currentObject.name : "N/A";
				var currentVal = currentObject.hasOwnProperty(prop) ? currentObject[prop] : "";
				
				//TODO - improve how we deal with bool
				if (currentVal != editedVal) {
					stageRows.push([resource, id, name, prop, currentVal, editedVal]);
				}    
			}
		}
	}
		
	//If no updates, return
	if (stageRows.length == 0) return;
		
	var ReviewSheet = utilGetSheet("Review", false);
	ReviewSheet.getRange(1 + ReviewSheet.getLastRow(), 1, stageRows.length, stageRows[0].length).setValues(stageRows).setNumberFormat("@");
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


/** STRUCUTRE AND FORMATTING **/
function resizeSheets() {
	var sheets = SpreadsheetApp.getActiveSpreadsheet().getSheets();
	for (var i = 0; i < sheets.length; i++) {

		for (var j = 1; j <= sheets[i].getLastColumn(); j++) {
			sheets[i].autoResizeColumn(j);
			if (sheets[i].getColumnWidth(j) > 500) sheets[i].setColumnWidth(j, 500);
		}
		
	}  
}

function resizeSheet(sheetName) {
	var sheet = utilGetSheet(sheetName, false);
	for (var j = 1; j <= sheet.getLastColumn(); j++) {
		sheet.autoResizeColumn(j);
		if (sheet.getColumnWidth(j) > 500) sheet.setColumnWidth(j, 500);
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

function utilTimeStamp() {
	return new Date().toISOString().substring(0, 16); 
}

/** GUI **/
function onInstall(e) {
	onOpen();
}

function onOpen() {
	SpreadsheetApp.getUi() // Or DocumentApp or FormApp.
		.createMenu("DHIS2")
		.addItem("Fetch metadata", "actionFetch")
		.addItem("Review metadata changes", "actionReview")
		.addItem("Push metadata changes to DHIS2", "actionPush")
		.addSeparator()
		.addItem("Add data element/indicator group column", "actionGroupSet")
		.addSeparator()
		.addSubMenu(SpreadsheetApp.getUi().createMenu('Configuration')
		.addItem("Server connection", "actionConnection")
		.addItem("Default metadata settings", "actionDefault")
		.addSeparator()
		.addItem("Clear change log", "actionResetLog")
		.addSeparator()
		.addItem("Remove URL", "actionResetUrl")
		.addItem("Remove username", "actionResetUsername"))
		.addToUi();
}


function actionFetch() {
	connectOrAuthenticate(1);
}
function actionReview() {
	connectOrAuthenticate(2);
}
function actionPush() {
	connectOrAuthenticate(3);
}
function actionGroupSet() {
	connectOrAuthenticate(4);
}
function actionDefault() {
	defaultResources();
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
function actionConnection() {
	connectOrAuthenticate(0);
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
	var r = [];
	for (var i = 9; i <= sheet.getLastRow(); i++) {
		r.push({
			"resource": sheet.getRange(i, 1).getValue(),
			"fields": sheet.getRange(i, 2).getValue(),
			"filter": sheet.getRange(i, 3).getValue(),
			"editable": sheet.getRange(i, 4).getValue().split(",")
		});
	}
	

	return r;
}

function defaultResources() {
	
	//Make headings
	var sheet = utilGetSheet("Settings", false);
	sheet.getRange(8, 1).setValue(["resource"]);
	sheet.getRange(8, 2).setValue(["fields"]);
	sheet.getRange(8, 3).setValue(["filter"]);
	sheet.getRange(8, 4).setValue(["editable"]);
	
	var r = [
		{"resource": "indicatorGroups",
			"fields": "id,lastUpdated,code,name,shortName,publicAccess",
			"filter": null,
			"editable": "code,name,shortName,publicAccess"
		},
		{"resource": "indicators",
			"fields": "id,lastUpdated,code,name,shortName,description,numeratorDescription,numerator,denominatorDescription,denominator,annualized,indicatorType[name],legendSets[name],publicAccess,",
			"filter": null,
			"editable": "code,name,shortName,description,numeratorDescription,numerator,denominatorDescription,denominator,annualized,publicAccess"
		},
		{"resource": "dashboards",
			"fields": "id,lastUpdated,name,publicAccess",
			"filter": null,
			"editable": "name,publicAccess"
		},
		{"resource": "charts",
			"fields": "id,lastUpdated,name,description,publicAccess",
			"filter": null,
			"editable": "name,description,publicAccess"
		},
		{"resource": "reportTables",
			"fields": "id,lastUpdated,name,description,publicAccess",
			"filter": null,
			"editable": "name,description,publicAccess"
		},
		{"resource": "maps",
			"fields": "id,lastUpdated,name,description,publicAccess",
			"filter": null,
			"editable": "name,description,publicAccess"
		},
		{"resource": "categories",
			"fields": "id,lastUpdated,code,name,dataDimensionType,dataDimension,categoryOptions[name],publicAccess",
			"filter": null,
			"editable": "code,name,publicAccess"
		},
		{"resource": "categoryOptions",
			"fields": "id,lastUpdated,code,name,shortName,publicAccess",
			"filter": null,
			"editable": "code,name,shortName,publicAccess"
		},
		{"resource": "categoryCombos",
			"fields": "id,lastUpdated,code,name,dataDimensionType,skipTotal,categories[name],publicAccess",
			"filter": null,
			"editable": "code,name,publicAccess"
		},
		{"resource": "categoryOptionCombos",
			"fields": "id,lastUpdated,code,name,categoryCombo[name],attributeValues[name],categoryOptions[name]",
			"filter": null,
			"editable": "code"
		},
		{"resource": "categoryOptionGroupSets",
			"fields": "id,lastUpdated,code,name,dataDimensionType,dataDimension,categoryOptionGroups[name],publicAccess",
			"filter": null,
			"editable": "code,name,publicAccess"
		},
		{"resource": "categoryOptionGroups",
			"fields": "id,lastUpdated,code,name,shortName,dataDimensionType,categoryOptions[name],publicAccess",
			"filter": null,
			"editable": "code,name,shortName,publicAccess"
		},
		{"resource": "dataElementGroups",
			"fields": "id,lastUpdated,code,name,shortName,publicAccess",
			"filter": null,
			"editable": "code,name,shortName,publicAccess"
		},
		{"resource": "dataElements",
			"fields": "id,lastUpdated,code,name,shortName,formName,description,categoryCombo[name],aggregationType,domainType,zeroIsSignificant,publicAccess,userGroupAccesses[name]",
			"filter": null,
			"editable": "code,name,shortName,formName,description,publicAccess"
		},
		{"resource": "dataSets",
			"fields": "id,lastUpdated,code,name,shortName,description,periodType,dataElementDecoration,timelyDays,publicAccess",
			"filter": null,
			"editable": "code,name,shortName,description,publicAccess"
		}
	];  
	
	for (var i = 0; i < r.length; i++) {
		sheet.getRange(9+i, 1).setValue([r[i].resource]);
		sheet.getRange(9+i, 2).setValue([r[i].fields]);
		sheet.getRange(9+i, 3).setValue([r[i].filter]);
		sheet.getRange(9+i, 4).setValue([r[i].editable]);
	}
	
	resizeSheet("Settings"); 
}

function dataElementGroupSet() {
	var sheet = utilGetSheet("Settings", false);
	return sheet.getRange(5,2).getValue();  
}

function indicatorGroupSet() {
	var sheet = utilGetSheet("Settings", false);
	return sheet.getRange(6,2).getValue();  
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
