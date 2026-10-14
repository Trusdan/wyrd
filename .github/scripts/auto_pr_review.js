const fs = require('fs');

const MAX_DIFF_CHARS = 20000;

function redactLargeDiff(diff) {
  if (!diff) return 'No diff available.';
  if (diff.length <= MAX_DIFF_CHARS) return diff;
  return `${diff.slice(0, MAX_DIFF_CHARS)}\n\n[diff truncated for review]`;
}

async function main() {
  const eventPath = process.env.GITHUB_EVENT_PATH;
  const token = process.env.GITHUB_TOKEN;
  const openAiKey = process.env.OPENAI_API_KEY;

  if (!eventPath || !fs.existsSync(eventPath)) {
    console.log('No GitHub event payload. Skipping AI review.');
    return;
  }

  if (!token) {
    console.log('GITHUB_TOKEN is missing. Skipping AI review.');
    return;
  }

  if (!openAiKey) {
    console.log('OPENAI_API_KEY is not set. Skipping AI review.');
    return;
  }

  const event = JSON.parse(fs.readFileSync(eventPath, 'utf8'));
  const pr = event.pull_request;
  const owner = event.repository.owner.login;
  const repo = event.repository.name;
  const prNumber = pr.number;

  let diff = '';
  if (fs.existsSync('pr.diff')) {
    diff = fs.readFileSync('pr.diff', 'utf8');
  }

  const trimmedDiff = redactLargeDiff(diff);
  const prompt = `You are an experienced code reviewer. Review this pull request.

PR title: ${pr.title || '<untitled>'}
PR body: ${pr.body || '<no description>'}

Give:
1. A brief summary of what changed.
2. The top three risks or issues to watch for.
3. Any missing tests or validation steps.
4. Keep the response concise.

Only comment on code that is directly visible in the diff. Do not invent facts beyond the diff.

Diff:
${trimmedDiff}`;

  const llmResponse = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${openAiKey}`,
    },
    body: JSON.stringify({
      model: 'gpt-4o-mini',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 800,
      temperature: 0.2,
    }),
  });

  if (!llmResponse.ok) {
    const body = await llmResponse.text();
    throw new Error(`OpenAI API error: ${llmResponse.status} ${body}`);
  }

  const llmJson = await llmResponse.json();
  const reviewText = llmJson.choices?.[0]?.message?.content?.trim();

  if (!reviewText) {
    throw new Error('OpenAI returned an empty response.');
  }

  const commentBody = `### Automated PR review\n\n${reviewText}`;

  const response = await fetch(`https://api.github.com/repos/${owner}/${repo}/issues/${prNumber}/comments`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ body: commentBody }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`GitHub comment error: ${response.status} ${body}`);
  }

  console.log('Automated PR review posted successfully.');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
