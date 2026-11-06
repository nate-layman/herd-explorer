# Ask page (ask.html)

Ask questions about the HERD data in plain language. The AI model never sees the database: it writes SQL, your browser runs it, and the model reads the results and answers. The approach comes from Data Crawler Carl, an open-source AI data explorer from AI4RA.

## Keys

Bring your own key; paste it in the API key box and click Use key, or open the page from a link like ask.html?key=... (read once and removed from the address bar). The key stays in that browser tab (session storage) and goes only to its own provider, chosen by prefix:

- mr2_ : University of Idaho MindRouter, model {mindrouter_model}
- sk-ant- : Anthropic Claude, model {anthropic_model}
- other sk- keys: OpenAI, model {openai_model}
- anything else: Google Gemini, model {gemini_model}, the best model on Google's free tier

MindRouter keys reach MindRouter through the AI4RA lakehouse proxy. Anthropic and OpenAI keys are not free: each question is billed to the account that owns the key.

To get a free Gemini key, go to Google AI Studio (https://aistudio.google.com/apikey) and sign in with a Google account. On a first visit a key is created for you; otherwise click Create API Key and choose a project with no billing account, because a project linked to billing is charged at paid rates. Free keys need no credit card, but they have limits per minute and per day (https://ai.google.dev/gemini-api/docs/rate-limits), and one question can use several requests. Google may use what you send to improve its products, and its reviewers may read it, so don't enter anything sensitive. The drop-downs under the key box on the Ask page repeat these steps.

Forget clears the key. New starts a new conversation. The conversation is kept while you move around the site in the same browser tab: leave Ask and come back, and your questions, answers and charts are still there, and follow-up questions keep their context. Closing the browser tab, or New, clears it. Like the key, it stays in the browser and is not sent anywhere until you ask another question.

## How an answer is made

1. The model is told the tables, every measure with its meaning and coverage, the institution types, and rules for answering.
2. It writes a SQL query. Your browser allows only a single read-only SELECT (no file or web access, no writes, no extensions) and caps results at 1,000 rows.
3. Up to 60 rows go back to the model, which explains them. If a query failed, it can write a corrected one, up to three rounds per question. If it is still querying after three, it must answer from what the queries returned, using only those numbers, or say plainly that it could not get the answer. It never estimates or fills in missing numbers. Such answers carry a note that all query attempts were used.
4. Charts are descriptions (type, a query, which columns go where) that the page checks and draws itself; nothing the model writes runs as code.
5. Every answer has Show the SQL panels with the exact queries and results.
6. For help using the site or questions about methods, the model can read these help documents; the answer lists which ones it read.

## What leaves your browser

Your questions, the description of the data, the query results, and any help documents the model asks for go to the provider your key belongs to. The HERD data themselves stay in your browser.

## Limits

- The model can misread a question or pick the wrong measure; check important numbers in Show the SQL, or on Trends or Compare.
- Answers cover FY {first_year} to FY {last_year}; questions about the future are pointed to the projections.
- Answer quality depends on the model behind your key.
