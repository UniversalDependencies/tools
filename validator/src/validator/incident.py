import sys
import os
from enum import Enum



class TestClass(Enum):
    INTERNAL = 0
    UNICODE = 1
    FORMAT = 2
    MORPHO = 3
    SYNTAX = 4
    ENHANCED = 5
    COREF = 6
    METADATA = 7
    WARNING = 8 ###!!! temporarily needed because downstream scripts expect it on output

    def __str__(self):
        return self.name

    def __lt__(self, other):
        return self.value < other.value


class IncidentType(Enum):
    ERROR = 1
    WARNING = 0



class Incident:
    """
    Instances of this class describe individual errors or warnings in the input
    file.
    """
    # We can modify the class-level defaults before a batch of similar tests.
    # Then we do not have to repeat the shared parameters for each test.
    default_level = 1
    default_testclass = TestClass.FORMAT
    default_testid = 'generic-error'
    default_message = 'No error description provided.'
    default_lineno = None
    def __init__(self, state, config, level=None, testclass=None, testid=None, message=None, lineno=None, nodeid=None, explanation=''):
        self.state = state
        self.config = config

        # Validation level to which the incident belongs. Integer 1-5.
        self.level = self.default_level if level == None else level
        # Thematic area to which the incident belongs: Format, Meta, Morpho,
        # Syntax, Enhanced, Coref, Warning.
        self.testclass = self.default_testclass if testclass == None else testclass
        # Identifier of the test that lead to the incident. Short string.
        self.testid = self.default_testid if testid == None else testid
        # Verbose description of the error for the user. It does not have to be
        # identical for all errors with the same testid because it can contain
        # instance-specific data (e.g. the word form).
        self.message = self.default_message if message == None else message
        # Additional more verbose information. To be printed with the first
        # incident of a given type.
        self.explanation = explanation
        # File name. The default is the file from which we are reading right
        # now ('-' if reading from STDIN).
        self.filename = 'STDIN' if state.current_file_name == '-' else os.path.basename(state.current_file_name)
        # Line number. The default is the most recently read line as recorded
        # in the state; but in most cases we need to get the number
        # during instantiation, as the most recently read line is the last line
        # of the sentence, and the error was found on one of the words of the
        # sentence.
        self.lineno = lineno if lineno != None else self.default_lineno if self.default_lineno != None else state.current_line
        if self.lineno < 0:
            self.lineno = state.sentence_line
        # Current (most recently read) sentence id.
        self.sentid = state.sentence_id
        # ID of the node on which the error occurred (if it pertains to one node).
        self.nodeid = nodeid

    def report(self):
        testclass_to_report = TestClass.WARNING if self.get_type() == IncidentType.WARNING else self.testclass
        # Even if we should be quiet, at least count the error.
        self.state.error_counter[testclass_to_report] = self.state.error_counter.get(testclass_to_report, 0)+1
        if not 'max_store' in self.config or self.config['max_store'] <= 0 or len(self.state.error_tracker[testclass_to_report]) < self.config['max_store']:
            self.state.error_tracker[testclass_to_report].append(self)
        if 'quiet' in self.config and self.config['quiet']:
            return
        # Suppress error messages of a type of which we have seen too many.
        if 'max_err' in self.config and self.config['max_err'] > 0 and self.state.error_counter[testclass_to_report] > self.config['max_err']:
            if self.state.error_counter[testclass_to_report] == self.config['max_err'] + 1:
                print(f'...suppressing further errors regarding {testclass_to_report}', file=sys.stderr)
            return # suppressed
        # If we are here, the error message should really be printed.
        # Address of the incident.
        address = f'Line {self.lineno} Sent {self.sentid}'
        # Insert file name if there are several input files.
        if 'n_files' in self.config and self.config['n_files'] > 1:
            address = f'File {self.filename} ' + address
        # Classification of the incident.
        levelclassid = f'L{self.level} {testclass_to_report} {self.testid}'
        # Message (+ explanation, if this is the first error of its kind).
        message = self.message
        if self.explanation and self.explanation not in self.state.explanation_printed:
            message += "\n\n" + self.explanation + "\n"
            self.state.explanation_printed.add(self.explanation)
        print(f'[{address}]: [{levelclassid}] {message}', file=sys.stderr)



class Error(Incident):
    def get_type(self):
        return IncidentType.ERROR

    def __repr__(self):
        out_str = f"[Line {self.lineno+1} Sent {self.sentid}]: [L{self.level} {self.testclass} {self.testid}] {self.message}"
        return out_str



class Warning(Incident):
    def get_type(self):
        return IncidentType.WARNING

    def __repr__(self):
        out_str = f"[Line {self.lineno+1} Sent {self.sentid}]: [L{self.level} {self.testclass} {self.testid}] {self.message}"
        return out_str
