def serialize_output(incidents, output_fhandle, explanations, lines_content):

    for incident in incidents:
        print(incident)


    if not incidents:
        print("*** PASSED ***")
    else:
        print(f"*** FAILED *** with {len(incidents)} error(s)")
