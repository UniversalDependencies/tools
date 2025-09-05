
def serialize_output(incidents, format, output_fhandle):

	if not incidents:
		print(">>>>>>>>> PASSED!")
	else:
		print(">>>>>>>>> FAILED:", incidents)