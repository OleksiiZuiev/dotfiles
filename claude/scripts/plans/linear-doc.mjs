// A plan whose home is a Linear document, read live through lib/linear.mjs. The document's `## Tasks`
// section lists the member tickets; each ticket links back with a `Plan: <document URL>` line in its
// body. The writing side is ~/.claude/skills/plan-homes/linear-doc.md.
import { fetchIssues, linearRequest, ticketStatus } from '../lib/linear.mjs';

// A plan's status is read on demand, not while a list is drawn, so a slow answer beats a failed one.
const TIMEOUT_MS = 15000;
const TICKET_ID = /\b[A-Z][A-Z0-9]*-\d+\b/g;
const TICKET_FIELDS = `title description state { name type }
  inverseRelations { nodes { type issue { identifier state { name type } } } }`;

// A document is named by its slugId, the last part of its URL: renaming the document changes the
// title part of the URL and keeps the slugId, and an old URL still opens it.
export function documentSlugId(text) {
  return text?.match(/\/document\/([\w-]+)/)?.[1].split('-').at(-1) ?? null;
}

function planSlugId(description) {
  return documentSlugId(description?.match(/^Plan:(.*)$/m)?.[1]);
}

function workspace(description) {
  return description?.match(/^Workspace:(.*)$/m)?.[1].trim() || null;
}

async function readDocument(url) {
  const slugId = documentSlugId(url);
  if (!slugId) throw new Error(`not a Linear document URL: ${url}`);
  const data = await linearRequest('query ($id: String!) { document(id: $id) { title content } }', { id: slugId }, { timeoutMs: TIMEOUT_MS });
  if (!data?.document) throw new Error(`Linear has no document ${url}`);
  return { slugId, ...data.document };
}

export async function documentTitle(url) {
  return (await readDocument(url)).title;
}

function memberIds(content) {
  const section = content.match(/^## Tasks[^\n]*\n([\s\S]*?)(?=^## |(?![\s\S]))/m)?.[1] ?? '';
  return [...new Set(section.match(TICKET_ID) ?? [])];
}

export async function linearDocStatus(plan) {
  const doc = await readDocument(plan.locator);
  const ids = memberIds(doc.content);
  const tickets = await fetchIssues(ids, TICKET_FIELDS, { timeoutMs: TIMEOUT_MS });
  const { issues } = await linearRequest(
    'query ($text: String!) { issues(first: 250, filter: { description: { contains: $text } }) { nodes { identifier description } } }',
    { text: doc.slugId }, { timeoutMs: TIMEOUT_MS });

  const members = ids.map((id) => {
    const ticket = tickets.get(id);
    if (!ticket) return { id, status: 'missing', title: '', blockers: [], workspace: null, planSlugId: null };
    const blockers = ticket.inverseRelations.nodes
      .filter((relation) => relation.type === 'blocks')
      .map((relation) => ({ id: relation.issue.identifier, status: ticketStatus(relation.issue.state) }))
      .filter((blocker) => blocker.status !== 'done');
    return { id, status: ticketStatus(ticket.state), title: ticket.title, blockers,
      workspace: workspace(ticket.description), planSlugId: planSlugId(ticket.description) };
  });
  const drift = [];
  for (const member of members) {
    if (member.status === 'missing') drift.push(`${member.id} is listed under ## Tasks but Linear does not know it`);
    else if (member.planSlugId !== doc.slugId) drift.push(`${member.id} is listed under ## Tasks but does not link back with Plan:`);
  }
  for (const issue of issues.nodes) {
    if (planSlugId(issue.description) === doc.slugId && !ids.includes(issue.identifier)) {
      drift.push(`${issue.identifier} links to the plan with Plan: but is not listed under ## Tasks`);
    }
  }
  return { members: members.map(({ planSlugId: _planSlugId, ...member }) => member), drift };
}
