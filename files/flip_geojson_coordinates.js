// flip_geojson_coordinates.js
//
// Swaps longitude/latitude in a GeoJSON file — for fixing exports where
// coordinates are in [lat, lon] order (DHIS2 and the GeoJSON spec
// require [lon, lat]; sources like Google Maps use the reverse).
//
// Works on any nesting depth, so Point, LineString, Polygon and
// MultiPolygon geometries are all handled, in either a GeoJSON
// FeatureCollection or a DHIS2 {"organisationUnits": [...]} payload.
//
// Usage:  node flip_geojson_coordinates.js input.json output.json
//
// To import org unit geometry from GeoJSON, use DHIS2's native import:
//   POST /api/organisationUnits/geometry  (Maintenance app > Import GeoJSON)
// matching features to org units by id or a chosen property/attribute.

'use strict';

const fs = require('fs');

const [inputFile, outputFile] = process.argv.slice(2);
if (!inputFile || !outputFile) {
    console.error('Usage: node flip_geojson_coordinates.js input.json output.json');
    process.exit(1);
}

// [a, b] pairs of numbers are flipped; arrays of arrays recurse.
function flip(coords) {
    if (!Array.isArray(coords)) return coords;
    if (coords.length === 2 && typeof coords[0] === 'number' && typeof coords[1] === 'number') {
        return [coords[1], coords[0]];
    }
    return coords.map(flip);
}

const data = JSON.parse(fs.readFileSync(inputFile, 'utf8'));

let flipped = 0;
const items = data.features || data.organisationUnits;
if (!items) {
    console.error('Input has neither "features" (GeoJSON) nor "organisationUnits" (DHIS2 payload)');
    process.exit(1);
}
for (const item of items) {
    if (item.geometry && item.geometry.coordinates) {
        item.geometry.coordinates = flip(item.geometry.coordinates);
        flipped++;
    }
}

fs.writeFileSync(outputFile, JSON.stringify(data, null, 1));
console.log(`Flipped coordinates of ${flipped} geometries -> ${outputFile}`);
