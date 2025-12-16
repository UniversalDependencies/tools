import logging
from logging.handlers import RotatingFileHandler
import os

CONSOLE_FORMAT = "[%(filename)s:%(lineno)s - %(funcName)20s()]  %(message)s"

def setup_logging(logger):

	log_file = os.getenv("LOG_FILE", "validate.log")
	error_file = os.getenv("ERROR_FILE", "validate.err")

	log_level = os.getenv("LOG_LEVEL", "DEBUG").upper()
	logger.setLevel(getattr(logging, log_level, logging.DEBUG))

	file_handler = RotatingFileHandler(log_file, maxBytes=5 * 1024 * 1024, backupCount=3)
	file_handler.setLevel(logging.DEBUG)

	error_handler = logging.FileHandler(error_file, "w", encoding="utf-8")
	error_handler.setLevel(logging.ERROR)

	console_handler = logging.StreamHandler()
	console_handler.setFormatter(logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s'))
	console_handler.setFormatter(logging.Formatter(CONSOLE_FORMAT))
	console_handler.setLevel(logging.DEBUG)

	logger.addHandler(console_handler)

	formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
	file_handler.setFormatter(formatter)
	error_handler.setFormatter(formatter)

	logger.addHandler(file_handler)
	logger.addHandler(error_handler)


def pprint(args):

	ret_str = ""
	for key, value in args.items():
		ret_str += f"{key:40} - {str(value):80}\n"

	return ret_str
