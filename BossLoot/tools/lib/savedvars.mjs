// Reading the saved-variables files the game writes (WTF/Account/<name>/
// SavedVariables/<Addon>.lua): a small part of Lua -- assignments of tables,
// strings, numbers, booleans and nil, with "-- [n]" comments after list items.

export function parseSavedVariables(text) {
  let i = 0;
  const fail = (what) => { throw new Error(`saved variables: ${what} at ${i}`); };

  const skip = () => {
    for (;;) {
      while (i < text.length && /\s/.test(text[i])) i++;
      if (text.startsWith('--[[', i)) {
        const end = text.indexOf(']]', i);
        if (end < 0) fail('unterminated comment');
        i = end + 2;
      } else if (text.startsWith('--', i)) {
        while (i < text.length && text[i] !== '\n') i++;
      } else {
        return;
      }
    }
  };

  const expect = (c) => {
    skip();
    if (text[i] !== c) fail(`expected "${c}"`);
    i++;
  };

  const identifier = () => {
    const match = /^[A-Za-z_][A-Za-z0-9_]*/.exec(text.slice(i, i + 200));
    if (!match) return null;
    i += match[0].length;
    return match[0];
  };

  const string = () => {
    const quote = text[i++];
    let out = '';
    for (;;) {
      if (i >= text.length) fail('unterminated string');
      const c = text[i++];
      if (c === quote) return out;
      if (c !== '\\') { out += c; continue; }
      const e = text[i++];
      if (e === 'n') out += '\n';
      else if (e === 't') out += '\t';
      else if (e === 'r') out += '\r';
      else if (/[0-9]/.test(e)) {
        let digits = e;
        while (digits.length < 3 && /[0-9]/.test(text[i])) digits += text[i++];
        out += String.fromCharCode(Number(digits));
      } else out += e;
    }
  };

  let value;

  const table = () => {
    i++; // {
    const out = {};
    let position = 1;
    for (;;) {
      skip();
      if (i >= text.length) fail('unterminated table');
      if (text[i] === '}') { i++; return out; }
      if (text[i] === '[') {
        i++;
        const key = value();
        expect(']');
        expect('=');
        out[String(key)] = value();
      } else {
        const start = i;
        const name = identifier();
        skip();
        if (name !== null && text[i] === '=' && text[i + 1] !== '=') {
          i++;
          out[name] = value();
        } else {
          i = start;
          out[String(position++)] = value();
        }
      }
      skip();
      if (text[i] === ',' || text[i] === ';') i++;
    }
  };

  value = () => {
    skip();
    const c = text[i];
    if (c === '{') return table();
    if (c === '"' || c === "'") return string();
    if (text.startsWith('true', i)) { i += 4; return true; }
    if (text.startsWith('false', i)) { i += 5; return false; }
    if (text.startsWith('nil', i)) { i += 3; return null; }
    const match = /^-?(0x[0-9a-fA-F]+|\d+(\.\d+)?([eE][-+]?\d+)?|\.\d+)/.exec(text.slice(i, i + 64));
    if (!match) fail('expected a value');
    i += match[0].length;
    return Number(match[0]);
  };

  const vars = {};
  for (;;) {
    skip();
    if (i >= text.length) return vars;
    const name = identifier();
    if (name === null) fail('expected a name');
    expect('=');
    vars[name] = value();
  }
}
