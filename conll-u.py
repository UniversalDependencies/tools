#! /usr/bin/python

import sys

def abort_token(message):
    print >> sys.stderr, "Bad token. " + message + " (line " + str(line_no) + "):"
    print >> sys.stderr, line
    exit()

def abort_sentence(message):
    print >> sys.stderr, "Bad sentence (lines " + str(line_no - sent_length) + " to " + str(line_no) + "): " + message + "."
    exit()

def validate_comment():
    if tokens or words:
        print line

def validate_sentence():
    global int_id
    global float_id
    global sent_length
    global sent_words
    global sent_tokens
    if sent_length > 0:
        validate_tree()
        if tokens:
            print_tokens()
        if words:
            print_words()
        int_id = 0
        float_id = 0.0
        sent_length = 0
        sent_words = {}
        sent_tokens = {}

def print_tokens():
    global sent_tokens
    index = 0
    for key in sorted(sent_tokens):
        if sent_tokens[key][3] == "_": # find internal head of non-word token
            wordkey = float(key)
            while True:
                wordkey = wordkey + 0.1
                if not str(wordkey) in sent_words.keys():
                    wordkey = float(key)
                    break
                else:
                    head = sent_words[str(wordkey)][6]
                    if int(float(head)) != int(key):
                        while head != str(0):
                            head = sent_words[head][6]
                            if int(float(head)) == int(key):
                                break
                        if head == str(0):
                            break
            for i in range(2, 10):
                sent_tokens[key][i] = sent_words[str(wordkey)][i]
        if "." in sent_tokens[key][6]: # truncate decimal HEAD value
            sent_tokens[key][6] = str(int(float(sent_tokens[key][6]))) 
        print "\t".join(sent_tokens[key]) # print token
    print ""

def print_words():
    global sent_words
    remap = {}
    index = 0
    for key in sorted(sent_words): # renumber token IDs
        index += 1
        sent_words[key][0] = str(index)
        remap[key] = str(index)
    for key in sorted(sent_words): # renumber HEAD values
        if sent_words[key][6] != str(0):
            sent_words[key][6] = remap[sent_words[key][6]]
        print "\t".join(sent_words[key]) # print word
    print ""

def validate_tree():
    path_to_root = {} 
    seen = {}
    for key in sorted(sent_words): # check that all HEAD values are valid
        w = sent_words[key]
        head = w[6]
        if head != str(0) and not head in sent_words.keys():
            abort_sentence("HEAD index " + head + " is not a valid token ID")
        if head == key:
            abort_sentence("HEAD index " + head + " equal to token ID")
        path_to_root[id] = False
    path_to_root[str(0)] = True
    for key in sorted(sent_words): # check that the graph is acyclic
        for k in sorted(sent_words):
            seen[k] = False
        w = sent_words[key]
        head = w[6]
        while True:
            if head in path_to_root.keys() and path_to_root[head]:
                path_to_root[key] = True
                break
            else:
                if seen[head]:
                    abort_sentence("Cycle detected for word " + key)
                seen[head] = True
                head = sent_words[head][6]

def validate_token():
    global sent_length
    fields = line.split("\t")
    if len(fields) != 10: # check that there are 10 fields
        abort_token("Not 10 tab-separated fields")
    validate_id(fields[0])
    validate_string(fields[1], "FORM")
    if nonword(fields[2:10]): # validate nonword token
        sent_tokens[fields[0]] = fields
        sent_length += 1
    else: # validate word
        validate_string(fields[2], "LEMMA")
        validate_label(fields[3], cpostagset, "CPOSTAG")
        validate_string(fields[4], "POSTAG")
        validate_list(fields[5], "FEATS")
        validate_head(fields[6])
        validate_label(fields[7], deprelset, "DEPREL")
        validate_list(fields[8], "DEPS")
        validate_string(fields[9], "MISC")
        sent_words[fields[0]] = fields
        if not "." in fields[0]:
            sent_tokens[fields[0]] = fields
        sent_length += 1

def nonword(fields):
    for field in fields:
        if field != "_":
            return False
    return True

def validate_id(id):
    global int_id
    global float_id
    try:
        num_id = int(id)
    except ValueError:
        try:
            num_id = float(id)
        except ValueError:
            abort_token("Token ID not numeric")
        else:
            float_id += 0.1
            if num_id != float_id:
                abort_token("Invalid token ID. Expected: " + str(float_id) + " Found: " + str(num_id))
    else:
        int_id += 1
        float_id = float(int_id)
        if int(num_id) != int_id:
            abort_token("Invalid token ID. Expected: " + str(int_id) + " Found: " + str(int(num_id)))

def validate_head(head):
    try:
        h = float(head)
    except ValueError:
        abort_token("Invalid HEAD value '" + head + "'")

def validate_label(label, dictionary, field):
    if not label in dictionary.keys():
        abort_token("Invalid " + field + " '" + label + "'")

def validate_string(str, field):
    if str.count(" "):
        abort_token("Invalid " + field + " '" + str + "' containing whitespace")

def validate_list(str, field):
    if str != "_":
        items = str.split("|")
        if field == "FEATS":
            validate_feats(items)
        elif field == "DEPS":
            validate_deps(items)

def validate_feats(items):
    for item in items:
        try: 
            (attribute, value) = item.split("=")
        except ValueError:
            abort_token("Invalid FEATS item '" + item + "'")
        else:
            validate_label(item, featsset, "FEATS")

def validate_deps(items):
    for item in items:
        try:
            (head, deprel) = item.split(":")
        except ValueError:
            abort_token("Invalid DEPS item " + item)
        else:
            validate_label(deprel, deprelset, "DEPREL")

def process_input_args():
    global words
    global tokens
    global cpostagset
    global featsset
    global deprelset
    if len(sys.argv) != 5:
        print >> sys.stderr, "Usage: python extract.py (validate|tokens|words) cpostagset featsset deprelset"
        exit()
    elif sys.argv[1] == "words":
        words = True
    elif sys.argv[1] == "tokens":
        tokens = True
    elif sys.argv[1] != "validate":
        print >> sys.stderr, "Unknown argument: " + sys.argv[1]
        print >> sys.stderr, "Usage: python extract.py (validate|tokens|words)"
        exit()
    try: # load cpostagset
        f = open(sys.argv[2])
        cpostags = f.readlines()
        f.close()
    except IOError:
        print >> sys.stderr, "Could not load cpostagset '" + sys.argv[2] + "'"
        exit()
    else:
        for i in range(0, len(cpostags)):
            label = cpostags[i].rstrip()
            cpostagset[label] = i
    try: # load featsset
        f = open(sys.argv[3])
        feats = f.readlines()
        f.close()
    except IOError:
        print >> sys.stderr, "Could not open featsset file '" + sys.argv[3] + "'"
        exit()
    else:
        for i in range(0, len(feats)):
            label = feats[i].rstrip()
            featsset[label] = i
    try: # load deprelset
        f = open(sys.argv[4])
        deprels = f.readlines()
        f.close()
    except IOError:
        print >> sys.stderr, "Could not open deprelset file '" + sys.argv[4] + "'"
        exit()
    else:
        for i in range(0, len(deprels)):
            label = deprels[i].rstrip()
            deprelset[label] = i

# main 
words = False
tokens = False
cpostagset = {}
featsset = {}
deprelset = {}
line_no = 0
int_id = 0
float_id = 0.0
sent_length = 0
sent_words = {}
sent_tokens = {}

process_input_args()
for line in sys.stdin:
    line = line.rstrip()
    line_no += 1
    if line == "":
        validate_sentence()
    elif line[0] == "#":
        validate_comment()
    else:
        validate_token()
if not tokens and not words:
    print >> sys.stderr, "Valid CoNLL-U file!"
