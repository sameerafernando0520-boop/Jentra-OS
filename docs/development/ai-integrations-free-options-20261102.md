# Jentra AI: zero-charge options reviewed 2 November 2026

The owner requires a free route. OpenAI key creation is on hold. This task has
not created a key, purchased credits, enabled billing, or sent a model request.
This record is a pricing and compatibility assessment, not an installed provider
change or positive hosted acceptance result.

The owner subsequently authorized implementation and activation. The resulting
Cloudflare candidate is implemented, reviewed, tested and staged; activation
remains pending. See the separate
[2 November activation record](ai-integrations-free-activation-20261102.md) for
current implementation evidence and remaining hosted gates. The assessment
below retains its original research context.

## Recommended hosted route

Use **Cloudflare Workers AI on Workers Free**, limited to models available on
that plan. Its documented allowance is 10,000 Neurons per day. Neurons measure
compute, not requests. The allowance resets at 00:00 UTC. Requests above the free
limits fail; paid overage requires Workers Paid. Some models require a paid
billing method and must be excluded from this route.

Keep the account on Free, enable no paid upgrade or credit purchase, and provide
no fallback to a paid provider. At exhaustion, pause AI suggestions until the
allowance resets. Verify the actual account plan and model eligibility before
activation. This can keep AI inference charges at zero under the current free
terms; it does not promise unlimited availability or unchanged future terms.

Source: [Cloudflare Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/).

Cloudflare documents JSON-schema output support for selected models, although
schema errors still require handling. It also states that Workers AI customer
content is not used for model training. Standard stateless inference has a
retention commitment with documented exceptions; avoid adding prompt logging,
caching, or stateful storage as part of this change.

Sources: [JSON mode](https://developers.cloudflare.com/workers-ai/features/json-mode/),
[data usage](https://developers.cloudflare.com/workers-ai/platform/data-usage/).

## Alternatives and costs

| Route | AI service cost | Practical limit |
| --- | --- | --- |
| Current OpenAI adapter | Usage-priced | The configured GPT-4.1 Mini model has token charges. Eligible existing Pro/Business subscriptions may supply limited API credits; eligibility and a balance have not been verified here. |
| Cloudflare Workers AI Free | Zero within its allowance | Daily inference limit; select an eligible model and retain Free account status. |
| Ollama with local models and cloud features disabled | No cloud API usage fees | Uses the computer's memory, disk and electricity. A hosted service would depend on that computer remaining available. |
| Gemini API Free | Free quota for eligible projects/models | Limited availability and rate limits. Unpaid-service data-use terms need review before sending Jentra business information. |

Sources: [OpenAI model pricing](https://developers.openai.com/api/docs/models/gpt-4.1-mini),
[subscription API credits](https://developers.openai.com/api/docs/guides/chatgpt-api-credits),
[Ollama pricing](https://ollama.com/pricing),
[Ollama local-only mode](https://docs.ollama.com/faq#how-do-i-disable-ollamas-cloud-features),
[Gemini billing](https://ai.google.dev/gemini-api/docs/billing/).

A read-only check of this Windows computer reported about 7.7 GiB total memory
and 0.4 GiB free. Available memory changes during use. No local inference
benchmark or GPU suitability test was completed. Local Ollama is therefore an
alternative to assess, rather than a verified replacement on this computer.

## Jentra work required before activation

The current runtime constructs `OpenAIResponsesProvider`, reads
`W5_OPENAI_API_KEY`, and has an OpenAI-specific reviewed provider policy. A
Cloudflare token cannot be substituted for that key. The free route needs its
own adapter and reviewed provider/model configuration.

The replacement must retain authenticated evidence reads, immutable source
identity, bounded requests, validated proposal fields, exact token accounting,
quota reservations, and explicit handling of unknown outcomes. A documented
free tier does not establish trusted usage or a successful hosted response.

Before activation, verify the chosen model's current availability, schema and
usage fields, then test the adapter and genuine hosted outcomes. Recheck current
runtime authority separately. Keep the existing unresolved external delivery
under its original identity; selecting a free AI provider does not authorize a
resend or prove delivery acceptance.

This recommendation concerns AI inference charges. Existing Supabase resources
and any external delivery service keep their own plans and limits. No account
plan, provider configuration, deployment, migration, or delivery state was
changed by this assessment.
