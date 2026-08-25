/**
 * EMA app → Google Sheet receiver.
 *
 * Setup:
 *  1. Open your Google Sheet → Extensions → Apps Script. Replace the contents with this file.
 *  2. Deploy → New deployment → Type "Web app".
 *       Execute as: Me.   Who has access: Anyone.
 *  3. Copy the web app URL (ends in /exec) into the app's Settings page.
 *  4. Any time you edit this script, Deploy → Manage deployments → Edit → New version.
 *
 * Each POST appends (or updates, keyed by uid) one row. New question texts
 * automatically get new columns, so you can change the questions in the app
 * without touching the sheet.
 */
var SHEET_NAME = 'Responses';
var FIXED = ['uid', 'status', 'scheduled_at', 'opened_at', 'submitted_at', 'timezone', 'received_at'];

function doPost(e) {
  var lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    var data = JSON.parse(e.postData.contents);
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName(SHEET_NAME) || ss.insertSheet(SHEET_NAME);

    // Header row
    var lastCol = sheet.getLastColumn();
    var headers = lastCol > 0 ? sheet.getRange(1, 1, 1, lastCol).getValues()[0] : [];
    if (headers.length === 0) {
      headers = FIXED.slice();
      sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
      sheet.setFrozenRows(1);
    }
    var answers = data.answers || {};
    var newCols = [];
    Object.keys(answers).forEach(function (k) {
      if (headers.indexOf(k) < 0) { headers.push(k); newCols.push(k); }
    });
    if (newCols.length) {
      sheet.getRange(1, headers.length - newCols.length + 1, 1, newCols.length).setValues([newCols]);
    }

    // Build row in header order
    var record = {
      uid: data.uid, status: data.status, scheduled_at: data.scheduled_at,
      opened_at: data.opened_at, submitted_at: data.submitted_at,
      timezone: data.timezone, received_at: new Date().toISOString()
    };
    var row = headers.map(function (h) {
      if (h in record) return record[h] == null ? '' : record[h];
      return answers[h] == null ? '' : answers[h];
    });

    // Upsert by uid so retries never create duplicates
    var uidCol = headers.indexOf('uid') + 1;
    var existing = null;
    if (sheet.getLastRow() > 1) {
      var found = sheet.getRange(2, uidCol, sheet.getLastRow() - 1, 1)
        .createTextFinder(String(data.uid)).matchEntireCell(true).findNext();
      if (found) existing = found.getRow();
    }
    if (existing) sheet.getRange(existing, 1, 1, row.length).setValues([row]);
    else sheet.appendRow(row);

    return json({ ok: true, updated: !!existing });
  } catch (err) {
    return json({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

function doGet() { return json({ ok: true, message: 'EMA receiver is running' }); }

function json(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
