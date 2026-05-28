const fs = require('fs');
const appJs = fs.readFileSync('./public/app.js', 'utf8');

// Find all direct addEventListener calls on variables (not guarded by if)
const lines = appJs.split('\n');
const crashes = [];

// Build a map of which variables have null-checked guards
// Look for patterns like: varName.addEventListener('click' 
// where the previous non-blank line is NOT "if (varName)"
for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    
    // Match unguarded .addEventListener calls
    const match = line.match(/^([a-zA-Z_$][a-zA-Z0-9_$]*)\.addEventListener\(/);
    if (!match) continue;
    
    const varName = match[1];
    
    // Climb up to find preceding non-blank line
    let j = i - 1;
    while (j >= 0 && lines[j].trim() === '') j--;
    const prevLine = j >= 0 ? lines[j].trim() : '';
    
    // Check if the previous meaningful line is an "if (varName)" guard
    const isGuarded = prevLine.startsWith(`if (${varName}`) || prevLine.startsWith(`if(${varName}`);
    
    if (!isGuarded) {
        crashes.push({ lineNum: i+1, varName, prevLine, code: line.substring(0, 100) });
    }
}

console.log('Unguarded addEventListener calls (could crash if element is null):');
crashes.forEach(c => {
    console.log(`  Line ${c.lineNum}: ${c.varName}.addEventListener  |  prevLine: "${c.prevLine.substring(0,60)}"`);
});
console.log('\nTotal:', crashes.length);
