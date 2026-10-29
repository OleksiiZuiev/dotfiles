// A fake Linear for the tests of the scripts that read it: it answers like the real one. A document
// by its slugId, issues by aliased identifier (an unknown identifier nulls the whole `data` and is
// named by its alias in `errors`), and issues whose description contains a text. It reads the
// fixture on every request, so a test changes Linear by rewriting that file.
//
//   node fake-linear.mjs <fixture.json> <port file> [<request log>]
//
// The fixture is {documents: {<slugId>: {title, url, content}}, issues: {<identifier>: {title,
// description, state, blockedBy?}}}. The port is written once the server listens; with a request
// log, one line is appended per request.
import { createServer } from 'node:http';
import { appendFileSync, readFileSync, writeFileSync } from 'node:fs';

const [fixture, portFile, requestLog] = process.argv.slice(2);
const server = createServer((req, res) => {
  let body = '';
  req.on('data', (chunk) => (body += chunk));
  req.on('end', () => {
    if (requestLog) appendFileSync(requestLog, `${body}\n`);
    const { query, variables = {} } = JSON.parse(body);
    const { documents, issues } = JSON.parse(readFileSync(fixture, 'utf8'));
    const toIssue = (id) => ({
      identifier: id,
      title: issues[id].title,
      description: issues[id].description,
      state: issues[id].state,
      inverseRelations: { nodes: (issues[id].blockedBy ?? []).map((blocker) =>
        ({ type: blocker.type ?? 'blocks', issue: { identifier: blocker.id, state: issues[blocker.id].state } })) },
    });
    let reply;
    if (/document\(id:/.test(query)) {
      const doc = documents[variables.id];
      reply = doc ? { data: { document: doc } } : { data: null, errors: [{ message: 'Entity not found: Document' }] };
    } else if (/issues\(/.test(query)) {
      const ids = Object.keys(issues).filter((id) => issues[id].description.includes(variables.text));
      reply = { data: { issues: { nodes: ids.map(toIssue) } } };
    } else {
      const aliases = [...query.matchAll(/(\w+): issue\(id: "([^"]+)"\)/g)];
      const unknown = aliases.filter(([, , id]) => !issues[id]);
      reply = unknown.length
        ? { data: null, errors: unknown.map(([, alias]) => ({ message: 'Entity not found: Issue', path: [alias] })) }
        : { data: Object.fromEntries(aliases.map(([, alias, id]) => [alias, toIssue(id)])) };
    }
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify(reply));
  });
});
server.listen(0, '127.0.0.1', () => writeFileSync(portFile, String(server.address().port)));
