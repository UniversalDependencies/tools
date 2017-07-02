# UD v2 conversion script
Author: Sebastian Schuster (sebschu@stanford.edu) 

**NOTICE**: There is [a newer conversion script](https://github.com/udapi/udapi-python/tree/master/udapi/block/ud), which supports e.g. FEATS changes and `remnant`→`orphan`, in addition to all the changes supported by this script.

This script performs the following automatic updates to a treebank to be compliant with the v2 guidlines:

* Rename UPOS tag `CONJ` to `CCONJ`.
* Rename the `mwe` relation to `fixed`.
* Rename the `name` relation to `flat`.
* Rename the `dobj` relation to `obj`.
* Rename the `(nsubj|csubj|aux)pass` relations to `(nsubj|csubj|aux):pass`.
* Change some `nmod` relations to `obl` (wherever appropriate). Note that in some cases, 
  it is ambiguous whether an `nmod` relation should be `nmod` or `obl`. If this is the case, the script  
  adds the property `ManualCheck=Yes` to the `MISC` column of the relation.
* Reattach coordinating conjunctions and commas to the succeeding conjunct.
* (Designed only for English!) Change `neg` relations to `advmod` or `det`. 

Note that this script does NOT perform all required changes. In particular, it does NOT perform the following changes, which either have to be performed manually or using custom scripts.

* New treatment of gapped constructions (using `orphan` relations instead of `remnant` relations).
* Changes to morphological features.
* Addition of enhanced dependencies.
* Changes to tokenization.
* Changes to copular constructions.
* Changes to POS tags beyond renaming `CONJ` to `CCONJ`.

**IMPORTANT**: I only tested this script on the English treebank. It should also work for other languages, but if you run this script on any other treebank, make sure to do thorough manual checks.


## Usage

The script requires Python 3. You can run the script with the following command.

```
python convert.py PATH_TO_CONLLU_FILE > OUTPUT_PATH
```

The script will write the converted trees to stdout (which is piped to `OUTPUT_PATH` in the above command). Warnings (including the corresponding tree) are printed to stderr.
