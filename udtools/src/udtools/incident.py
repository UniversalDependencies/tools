from dataclasses import dataclass
from enum import Enum
from json import JSONEncoder

jenc = JSONEncoder()



class TestClass(Enum):
    INTERNAL = 0
    UNICODE = 1
    FORMAT = 2
    MORPHO = 3
    SYNTAX = 4
    ENHANCED = 5
    COREF = 6
    METADATA = 7

    def __str__(self):
        return self.name

    def __lt__(self, other):
        return self.value < other.value



class IncidentType(Enum):
    ERROR = 1
    WARNING = 0

    def __str__(self):
        return self.name

    def __lt__(self, other):
        return self.value < other.value



@dataclass(order=True)
class Reference:
    """
    Points to a position in the source file. Each incident (error or warning)
    has always a main anchor (reference) that is reported with the error.
    However, some errors may also relate to additional positions in the file,
    which can be then given as a list of Reference objects. As a minimum,
    a reference indicates the line number. If there were multiple input files,
    it should also indicate the file name, as line numbers reset when new file
    starts. Optionally, references can also indicate the sentence and node ids
    (if pointing to a node) to facilitate locating the target. Finally, the
    reference can include a comment which explain its relation to the incident.
    """
    filename: str
    lineno: int
    sentid: str = ''
    nodeid: str = ''
    comment: str = ''

    def json(self):
        """
        Returns the reference description in JSON format so it can be passed to
        external applications easily.
        """
        jsonlist = []
        jsonlist.append(f'"filename": {jenc.encode(str(self.filename))}')
        jsonlist.append(f'"lineno": "{str(self.lineno)}"')
        jsonlist.append(f'"sentid": {jenc.encode(str(self.sentid))}')
        jsonlist.append(f'"nodeid": "{str(self.nodeid)}"')
        jsonlist.append(f'"comment": {jenc.encode(self.comment)}')
        return '{' + ', '.join(jsonlist) + '}'



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
    def __init__(self, state, config, level=None, testclass=None, testid=None, message=None, lineno=None, nodeid=None, explanation='', references=[]):
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
        self.filename = state.get_current_file_name()
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
        # Additional references to nodes or other input lines, if needed.
        # List of Reference objects. Note that the main anchor is not included
        # in the list; it is described directly in filename, lineno, sentid and
        # nodeid parameters.
        self.references = references

    def json(self):
        """
        Returns the incident description in JSON format so it can be passed to
        external applications easily.
        """
        jsonlist = []
        jsonlist.append(f'"level": "{self.level}"')
        jsonlist.append(f'"type": "{str(self.get_type())}"')
        jsonlist.append(f'"testclass": "{str(self.testclass)}"')
        jsonlist.append(f'"testid": "{str(self.testid)}"')
        jsonlist.append(f'"filename": {jenc.encode(str(self.filename))}')
        jsonlist.append(f'"lineno": "{str(self.lineno)}"')
        jsonlist.append(f'"sentid": {jenc.encode(str(self.sentid))}')
        jsonlist.append(f'"nodeid": "{str(self.nodeid)}"')
        jsonlist.append(f'"message": {jenc.encode(str(self.message))}')
        jsonlist.append(f'"explanation": {jenc.encode(str(self.explanation))}')
        refjson = '[' + ', '.join([x.json() for x in self.references]) + ']'
        jsonlist.append(f'"references": {refjson}')
        return '{' + ', '.join(jsonlist) + '}'

    def _count_me(self):
        self.state.error_counter[self.get_type()][self.testclass] += 1
        # Return 0 if we are not over max_err.
        # Return 1 if we just crossed max_err (meaning we may want to print an explanation).
        # Return 2 if we exceeded max_err by more than 1.
        if 'max_err' in self.config and self.config['max_err'] > 0 and self.state.error_counter[self.get_type()][self.testclass] > self.config['max_err']:
            if self.state.error_counter[self.get_type()][self.testclass] == self.config['max_err'] + 1:
                return 1
            else:
                return 2
        else:
            return 0

    def _store_me(self):
        # self.state.error_tracker is a list of incidents.
        if 'max_store' in self.config and self.config['max_store'] > 0 and len(self.state.error_tracker) >= self.config['max_store']:
            return # we cannot store more incidents
        self.state.error_tracker.append(self)

    def __str__(self):
        # If we are here, the error message should really be printed.
        # Address of the incident.
        address = f'Line {self.lineno} Sent {self.sentid}'
        # Insert file name if there are several input files.
        if 'report_filename' in self.config and self.config['report_filename']:
            address = f'File {self.filename} ' + address
        # Classification of the incident.
        levelclassid = f'L{self.level} {self.testclass_to_report()} {self.testid}'
        # Message (+ explanation, if this is the first error of its kind).
        message = self.message
        if self.explanation and self.explanation not in self.state.explanation_printed:
            message += "\n\n" + self.explanation + "\n"
            self.state.explanation_printed.add(self.explanation)
        return f'[{address}]: [{levelclassid}] {message}'

    def __lt__(self, other):
        return self.lineno < other.lineno

    def confirm(self):
        """
        An Incident object is typically created at the time we know the incident
        (error or warning) really occurred. However, sometimes it is useful to
        prepare the object when we observe one necessary condition, and then
        wait whether we also encounter the other necessary conditions. Once we
        know that all conditions have been met, we should call this method. It
        will take care of registering the incident, reporting it, adjusting
        error counters etc. In the typical situation, one calls .confirm()
        immediately after one constructs the Incident object.
        """
        # Even if we should be quiet, at least count the error.
        too_many = self._count_me()
        self._store_me()
        # Check if this incident should be printed, and if so, print it.
        if not self.config['output'] or 'quiet' in self.config and self.config['quiet']:
            return
        if 'no_warnings' in self.config and self.config['no_warnings'] and self.is_warning():
            return
        if 'exclude' in self.config and self.testid in self.config['exclude']:
            return
        if 'include_only' in self.config and self.testid not in self.config['include_only']:
            return
        # Suppress error messages of a type of which we have seen too many.
        if too_many > 0:
            if too_many == 1:
                print(f'...suppressing further messages regarding {str(self.get_type())}/{str(self.testclass)}', file=self.config['output'])
            return # suppressed
        print(str(self), file=self.config['output'])

    def get_type(self):
        """ This method must be overridden in derived classes. """
        raise NotImplementedError()

    def is_error(self):
        return self.get_type() == IncidentType.ERROR

    def is_warning(self):
        return self.get_type() == IncidentType.WARNING

    def testclass_to_report(self):
        """ This method must be overridden in derived classes. """
        raise NotImplementedError()



class Error(Incident):
    def get_type(self):
        return IncidentType.ERROR
    def testclass_to_report(self):
        return str(self.testclass)



class Warning(Incident):
    def get_type(self):
        return IncidentType.WARNING
    def testclass_to_report(self):
        return 'WARNING'
