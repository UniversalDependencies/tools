"""
The CompiledRegexes module holds various regular expressions needed to
recognize individual elements of the CoNLL-U format, precompiled to speed
up parsing. Individual expressions are typically not enclosed in ^...$
because one can use re.fullmatch() if it is desired that the whole string
matches the expression.
"""

import regex as re

# Whitespace(s)
ws = re.compile(r"\s+")

# TODO: rename in 'two_ws'
# Exactly two whitespaces
ws2 = re.compile(r"\s\s")

# TODO: rename in 'integer'
# Integer
wordid = re.compile(r"[1-9][0-9]*")

# TODO: rename in 'integer_range'
# Multiword token id: range of integers.
# The two parts are bracketed so they can be captured and processed separately.
mwtid = re.compile(r"([1-9][0-9]*)-([1-9][0-9]*)")   # range of integers.

# TODO: rename in 'decimal'
# Empty node id: "decimal" number (but 1.10 != 1.1).
# The two parts are bracketed so they can be captured and processed separately.
enodeid = re.compile(r"([0-9]+)\.([1-9][0-9]*)")

# New document comment line. Document id, if present, is bracketed.
# ! Why not replacing \s with " "?
# ! proposal for new regex: "# newdoc(?: = (\S+))?"
newdoc = re.compile(r"#\s*newdoc(?:\s+(\S+))?")

# New paragraph comment line. Paragraph id, if present, is bracketed.
# ! proposal for new regex: "# newpar(?: = (\S+))?"
newpar = re.compile(r"#\s*newpar(?:\s+(\S+))?")

# Sentence id comment line. The actual id is bracketed.
# ! proposal for new regex: "# sent_id = (\S+)"
sentid = re.compile(r"#\s*sent_id\s*=\s*(\S+)")

# Sentence text comment line. The actual text is bracketed.
# ! proposal for new regex: "# text = (.*\S)"
text = re.compile(r"#\s*text\s*=\s*(.*\S)")

# Global entity comment is a declaration of entity attributes in MISC.
# It occurs once per document and it is optional (only CorefUD data).
# The actual attribute declaration is bracketed so it can be captured in the match.
# ! proposal for new regex: "# global\.Entity = (.+)"
# TODO: write test
global_entity = re.compile(r"#\s*global\.Entity\s*=\s*(.+)")

# TODO: rename in 'uppercase_string'
# UPOS tag.
upos = re.compile(r"[A-Z]+")

# Feature=value pair.
# Feature name and feature value are bracketed so that each can be captured separately in the match.
featval = re.compile(
    r"([A-Z][A-Za-z0-9]*(?:\[[a-z0-9]+\])?)=(([A-Z0-9][A-Z0-9a-z]*)(,([A-Z0-9][A-Z0-9a-z]*))*)"
    )
val = re.compile(r"[A-Z0-9][A-Za-z0-9]*") 	# ! why do we need this?
											# TODO: test?

# Basic parent reference (HEAD).
# TODO: rename in 'natural_number'
head = re.compile(r"(0|[1-9][0-9]*)")

# Enhanced parent reference (head).
# TODO: rename in 'decimal_withzero'
ehead = re.compile(r"(0|[1-9][0-9]*)(\.[1-9][0-9]*)?")

# Basic dependency relation (including optional subtype).
deprel = re.compile(r"[a-z]+(:[a-z]+)?")

# TODO: write test
# Enhanced dependency relation (possibly with Unicode subtypes).
# Ll ... lowercase Unicode letters
# Lm ... modifier Unicode letters (e.g., superscript h)
# Lo ... other Unicode letters (all caseless scripts, e.g., Arabic)
# M .... combining diacritical marks
# Underscore is allowed between letters but not at beginning, end, or next to another underscore.
edeprelpart_resrc = r'[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(_[\p{Ll}\p{Lm}\p{Lo}\p{M}]+)*'

# There must be always the universal part, consisting only of ASCII letters.
# There can be up to three additional, colon-separated parts: subtype, preposition and case.
# One of them, the preposition, may contain Unicode letters. We do not know which one it is
# (only if there are all four parts, we know it is the third one).
# ^[a-z]+(:[a-z]+)?(:[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(_[\p{Ll}\p{Lm}\p{Lo}\p{M}]+)*)?(:[a-z]+)?$
edeprel_resrc = '^[a-z]+(:[a-z]+)?(:' + edeprelpart_resrc + ')?(:[a-z]+)?$'
edeprel = re.compile(edeprel_resrc)