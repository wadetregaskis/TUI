# Investigations

This folder holds the committed summaries of investigations: one page each, for a question that
took measuring, probing or reading to answer, and whose answer someone will want again. A summary
says:

- **the question**, as it was asked, and by whom;
- **the answer**, up front, in a sentence or two;
- **the key measurements**, with how and on what each was taken (toolchain, OS, terminal and its
  version, commit), so that a reader can repeat one;
- **the reasoning** that gets from the measurements to the answer, including what was ruled out
  and why;
- **links**: to the code, the commits, the decisions entry and the living documents
  (for example `Terminals/Terminal compatibility survey.md`) that the answer changed.

A summary is written while its investigation is live, and stays here while the decision it informs
is open. When that decision lands, the summary moves to `Historical/Investigations/`, dated in its
name as `Historical/`'s other files are, so that this folder lists only what is still being decided.

## Working notes

`Documentation/Working notes/` is not committed: `.gitignore` excludes it, and it exists only on the
machine that made it. It holds an investigation's raw material — notes as they were taken, probe
programs and scripts, captured terminal output, traces, benchmark runs — which is large, easily
reproduced, or both. Nothing committed may depend on it: a document links to a summary here, never
into the working notes, and `Tools/validate-markdown-links.py` fails on a link into them, because
nobody else has those files. What a reader needs from an investigation belongs in its summary.

No summaries are here yet.
