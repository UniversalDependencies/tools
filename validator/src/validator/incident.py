from dataclasses import dataclass, field
from enum import Enum
import os

from validator.validate_lib import State

class TestClass(Enum):
    INTERNAL = 0
    UNICODE = 1
    FORMAT = 2
    MORPHO = 3
    SYNTAX = 4
    ENHANCED = 5
    COREF = 6
    METADATA = 7

class IncidentType(Enum):
    ERROR = 1
    WARNING = 0

# TODO: make abstract
@dataclass
class Incident:
    state: State = field(init=False) # TODO: check if this is actually necessary
    level: int = 1
    testclass: TestClass = TestClass.FORMAT
    testid: str = 'generic-error'
    message: str = 'No error description provided.'
    # Line number. The default is the most recently read line as recorded
    # in the state; but in most cases we need to get the number
    # during instantiation, as the most recently read line is the last line
    # of the sentence, and the error was found on one of the words of the
    # sentence.
    lineno: int = -1 # ?
    # File name. The default is the file from which we are reading right
    # now ('-' if reading from STDIN).
    filename: str = 'STDIN'
    # Current (most recently read) sentence id.
    sentid: str = None
    # ID of the node on which the error occurred (if it pertains to one node).
    nodeid: str = None

    def set_state(self, state):

        #self.state = state
        self.lineno = state.current_line

        if not state.current_file_name == '-':
            self.filename = os.path.basename(state.current_file_name)
        return self # !

        #self.sentid = self.state.sentence_id
        #self.nodeid = self.state.nodeid

    def __repr__(self):
        return self.testid

    # TODO: overwrite __str__ or __repr__
    # def report(self, state, args):
    #     # Even if we should be quiet, at least count the error.
    #     state.error_counter[self.testclass] = state.error_counter.get(self.testclass, 0)+1
    #     if args.quiet:
    #         return
    #     # Suppress error messages of a type of which we have seen too many.
    #     if args.max_err > 0 and state.error_counter[self.testclass] > args.max_err:
    #         if state.error_counter[self.testclass] == args.max_err + 1:
    #             print(f'...suppressing further errors regarding {self.testclass}', file=sys.stderr)
    #         return # suppressed
    #     # If we are here, the error message should really be printed.
    #     # Address of the incident.
    #     address = f'Line {self.lineno} Sent {self.sentid}'
    #     if self.nodeid:
    #         address += f' Node {self.nodeid}'
    #     # Insert file name if there are several input files.
    #     if len(args.input) > 1:
    #         address = f'File {self.filename} ' + address
    #     # Classification of the incident.
    #     levelclassid = f'L{self.level} {self.testclass} {self.testid}'
    #     # Message (+ explanation, if this is the first error of its kind).
    #     message = self.message
    #     if self.explanation and self.explanation not in state.explanation_printed:
    #         message += "\n\n" + self.explanation + "\n"
    #         state.explanation_printed.add(self.explanation)
    #     print(f'[{address}]: [{levelclassid}] {message}', file=sys.stderr)


@dataclass
class Error(Incident):
    def get_type(self):
        return IncidentType.ERROR

    def __repr__(self):
        return "ERROR: {}".format(self.testid)

@dataclass
class Warning(Incident):
    def get_type(self):
        return IncidentType.WARNING

    def __repr__(self):
        return "WARNING: {}".format(self.testid)