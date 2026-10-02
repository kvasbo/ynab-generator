# AGENTS.md

Ruby CLI that converts Norwegian bank exports to OFX for YNAB. See README.md
for what it does and how it works.

## Commands

```sh
bundle install
bundle exec rspec          # must pass before every commit
bin/convert <in> <out>     # try it on spec/fixtures
```

## Rules

- **Never commit real bank data.** Fixtures in `spec/fixtures/` are fictional
  and must stay that way: no real names, addresses, account/card numbers,
  KIDs, merchants or amounts. Check any new fixture, including inside binary
  files (xlsx shared strings, PDF text).
- Test first. Every parser change needs a spec; every new format needs an
  anonymised fixture and a spec before the parser.
- Keep it simple: plain Ruby, no new gems unless unavoidable.
- Supported Ruby: 3.2 and newer (CI runs 3.2–4.0).

## Adding a bank

1. Add an anonymised export to `spec/fixtures/`.
2. Write `spec/parsers/<bank>_spec.rb`.
3. Add `lib/ynab_ofx/parsers/<bank>.rb`: subclass `Parsers::Base`, set
   `extensions` and a `signature` regex matched against the file contents,
   implement `read_statements(path)` returning a `Statement` or an array of
   them.
4. Require it in `lib/ynab_ofx.rb` and add it to `Detector::PARSERS`.
5. Add it to the table in README.md.

## Conventions

- Amounts are `BigDecimal`; negative means money out.
- Use `fitid_for` from `Parsers::Base` so transaction IDs stay stable
  between runs. Changing how an existing parser builds the FITID key
  creates duplicates in YNAB for users who re-import.
- Zero-amount transactions are dropped centrally in `Parsers::Base#parse`.
- `spec/fixtures/build_handelsbank_mc_pdf.rb` regenerates the Handelsbanken
  PDFs; edit it rather than the PDFs.
