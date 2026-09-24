import re
import json

def separate_asm_line(current_line: str) -> dict:
    """ 
    take in assembly line as a string and separate it into components (address,
    opcode, optional operands, mnemonic, and comment)
    :param: current_line: a string representing the current line of I-8080 assembly
    :returns: dict: a dictionary representing the current line
    """

    # populate object with defaults
    elements = {
        'address': None,
        'opcode': None,
        'operand1': None,
        'operand2': None,
        'mnemonic': None,
        'comment': None
    }

    # get address
    address = None

    # regex pattern: white space followed by '0xDDDD'
    address_pattern = r'0x[0-9a-fA-F]{4}'

    # split the line of text at colon
    split_off_address = current_line.split(":")

    # now check to see if we have an address
    # if we don't return (we don't have a valid line of assembly here)
    if re.match(address_pattern, split_off_address[0]):
        address = split_off_address[0].strip()

    # return if not valid
    if not address:
        return {}

    # otherwise, assign address
    elements['address'] = address

    assembly, comment = get_mnemonic(current_line)
    elements['mnemonic'] = assembly
    elements['comment'] = comment

    opcode, operand1, operand2 = get_opcodes(split_off_address[1])
    elements['opcode'] = opcode
    elements['operand1'] = operand1
    elements['operand2'] = operand2

    return elements

def get_opcodes(line_no_address: str) -> tuple:
    """
    Separates the opcode and optional operands from assembly line
    """

    # set defaults
    opcode = None
    operand1 = None
    operand2 = None

    # are there operands? check for brackets
    split_off_brackets = line_no_address.split("[")
    if len(split_off_brackets) > 1:
        check_for_operands = split_off_brackets[1].split("]")

        get_hexcodes = check_for_operands[0].split(" ")
        if len(get_hexcodes) > 1:
            operand2 = get_hexcodes[1]
        if len(get_hexcodes) > 0:
            operand1 = get_hexcodes[0]

    # get opcode
    opcode = split_off_brackets[0].strip()
    opcode = opcode.split(" ")
    opcode = opcode[0]

    # return opcode and operands
    return opcode, operand1, operand2


def get_mnemonic(current_line: str) -> tuple:
    """
    Separates both the comment and the assembly mnemonic from a line of text
    """

    # set defaults
    assembly = None
    comment = None

    # separate comment from text
    split_off_comment = current_line.split(";")
    if len(split_off_comment) > 1:
        comment = split_off_comment[1].strip()

    # get assembly mnemonics (in between | and ;)
    split_off_mnemonic = split_off_comment[0].split("|")
    assembly = split_off_mnemonic[-1].strip()

    # return values: (assembly, comment)
    return assembly, comment

 
def read_asm_file(filename: str) -> list:
    """ 
    Ingest the contents of the .asm file with markup created during the disassembly
    process. This procedure depends heavily on the specific formatting I used,
    with procedure names that begin with a period on new lines
    """
    # regex pattern: white space or tab followed by 4 hex digits: '    0xDDDD'
    address_pattern = r'^[ \t]+0x[0-9a-fA-F]{4}'

    # title pattern: beginning with a '.' 
    # followed by alphanumeric character or underscore
    title_pattern = r"^\.\w+"

    # initialize array for all procedures
    procedures = []

    # collect data for current procedure
    current = {}

    # initialize variables
    running_description = ''
    proc_title = ''
    proc_assembly = []
    desc_printed = True

    with open('invaders.asm', 'r', encoding='utf-8') as file:

        # loop through code lines (excludes ROM data)
        for _ in range(5723):

            # read in current line
            current_line = file.readline()

            # returns if we hit end-of-file
            if not current_line:
                return 

            # check to see if this is the title of a procedure
            if re.match(title_pattern, current_line):
                # we've found a new procedure
                # time to add code and append
                current['code'] = proc_assembly
                procedures.append(current)

                # clear current for use in next procedure
                current = {}
                proc_assembly=[]
                desc_printed = False

                # get the first word until white space
                splitline = current_line.split(" ")
                proc_title = splitline[0].strip()
                current['procedure'] = proc_title

            # check to see if this is a line of assembly
            elif re.match(address_pattern, current_line):

                # if we've reached a procedure's first line of assembly
                # add the description to current
                # and clear assembly from previous procedure
                if not desc_printed and running_description.strip():

                    # strip semicolons from description
                    # then clean and store in current procedure
                    desc_no_semis = running_description.replace(';', '').strip()
                    filtered_desc = clean_description(desc_no_semis)
                    current['description'] = filtered_desc

                    # set True so we only do this once
                    desc_printed = True

                    # clear description and assembly list for next procedure
                    running_description = ''
                    proc_assembly = []

                # append current line of assembly to procedure
                assembly = separate_asm_line(current_line.strip())
                proc_assembly.append(assembly)


            else:
                # add to running description
                if current_line.strip():
                    running_description += current_line

    return procedures[1:]

def clean_description(current_description):
    """
    removes portions of a current description that are between two long lines 
    of asterisks or hyphens. Cleans up data so that major notes used in asm
    file are not included in individual procedures' records
    """

    # create regex patterns for asterisks and hyphens
    asterisk_pattern = r"\*{5,}"
    hyphen_pattern = r"-{5,}"

    # track whether we are exlcuding
    exclude_asterisk = False
    exclude_hyphen = False

    # create an array of included elements
    filtered_elements = []

    # split and filter
    split_description = current_description.split(" ")
    for element in split_description:

        # check for asterisks
        if element and re.match(asterisk_pattern, element):
            exclude_asterisk = not exclude_asterisk

        else:
            # check for hyphens
            if element and re.match(hyphen_pattern, element):
                exclude_hyphen = not exclude_hyphen

            else:
                # exclude parts between lines of asterisks or hyphens
                if not exclude_asterisk and not exclude_hyphen:
                    filtered_elements.append(element)

    # re-concatenate and return
    cleaned_description = " ".join(filtered_elements)
    return cleaned_description

def write_to_json(procedures: list) -> str:
    """ 
    converts the compiled list of procedures to a JSON file
    """
    with open('invaders_asm.json', 'w') as outfile:
        json.dump(procedures, outfile)

if __name__ == '__main__':
    space_invaders_file = 'invaders.asm'
    procedures = read_asm_file(space_invaders_file)
    write_to_json(procedures)
