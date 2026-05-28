const fs = require('fs');
let content = fs.readFileSync('./public/app.js', 'utf8');
const lines = content.split('\n');

// Remove lines 3322-3503 (0-indexed: 3321-3502) — the stale old send engine
// These are the duplicate updateSendFeeEstimate, appendSendLog, btnSendTroptions handler, and simulateSendTroptions
const startLine = 3321; // 0-indexed (line 3322 in 1-indexed)
const endLine = 3503;   // 0-indexed (line 3504 in 1-indexed, exclusive)

// Sanity check the range
console.log('Start of removed block:', lines[startLine].trim());
console.log('End of removed block (last removed):', lines[endLine - 1].trim());
console.log('First line after:', lines[endLine].trim());

// Remove the stale block
const newLines = [...lines.slice(0, startLine), ...lines.slice(endLine)];
console.log(`Removed ${endLine - startLine} lines. New total: ${newLines.length}`);

fs.writeFileSync('./public/app.js', newLines.join('\n'), 'utf8');
console.log('Done!');
