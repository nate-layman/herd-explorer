# Ask page (ask.html)

Ask questions about the HERD data in plain language. The AI model never sees the database: it writes SQL, your browser runs it, and the model reads the results and answers. The approach comes from Data Crawler Carl, an open-source AI data explorer from AI4RA.

## Keys

Bring your own key; paste it in the API key box and click Use key, or open the page from a link like ask.html?key=... (read once and removed from the address bar). The key stays in that browser tab (session storage) and goes only to its own provider, chosen by prefix:

- mr2_ : University of Idaho MindRouter
- sk-ant- : Anthropic Claude
- other sk- keys: OpenAI
- anything else: Google Gemini

Forget clears the key. New starts a new conversation.

## How an answer is made

1. The model is told the tables, every measure with its meaning and coverage, the institution types, and rules for answering.
2. It writes a SQL query. Your browser allows only a single read-only SELECT (no file or web access, no writes, no extensions) and caps results at 1,000 rows.
3. Up to 60 rows go back to the model, which explains them. If a query failed, it can write a corrected one, up to three rounds per question.
4. Charts are descriptions (type, a query, which columns go where) that the page checks and draws itself; nothing the model writes runs as code.
5. Every answer has Show the SQL panels with the exact queries and results.
6. For help using the site or questions about methods, the model can read these help documents; the answer lists which ones it read.

## What leaves your browser

Your questions, the description of the data, the query results, and any help documents the model asks for go to the provider your key belongs to. The HERD data themselves stay in your browser.

## Limits

- The model can misread a question or pick the wrong measure; check important numbers in Show the SQL, or on Trends or Compare.
- Answers cover FY {first_year} to FY {last_year}; questions about the future are pointed to the projections.
- Answer quality depends on the model behind your key.
