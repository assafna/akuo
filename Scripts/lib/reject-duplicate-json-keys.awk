# Detect duplicate top-level object keys before a property-list parser can
# normalize them away. Schema 1 keys are canonical ASCII and may not be escaped.
BEGIN {
    depth = 0
    in_string = 0
    escaped = 0
    capturing_key = 0
    previous = ""
}

{
    for (index_in_line = 1; index_in_line <= length($0); index_in_line++) {
        character = substr($0, index_in_line, 1)

        if (in_string) {
            if (escaped) {
                escaped = 0
                continue
            }
            if (character == "\\") {
                escaped = 1
                if (capturing_key) {
                    key_was_escaped = 1
                }
                continue
            }
            if (character == "\"") {
                in_string = 0
                if (capturing_key) {
                    if (key_was_escaped) {
                        print "manifest JSON keys must use canonical ASCII spelling" > "/dev/stderr"
                        exit 1
                    }
                    if (seen_key[key_text]) {
                        print "manifest contains a duplicate JSON key: " key_text > "/dev/stderr"
                        exit 1
                    }
                    seen_key[key_text] = 1
                    capturing_key = 0
                }
                previous = "string"
                continue
            }
            if (capturing_key) {
                key_text = key_text character
            }
            continue
        }

        if (character == " " || character == "\t" || character == "\r") {
            continue
        }
        if (character == "\"") {
            in_string = 1
            escaped = 0
            capturing_key = (depth == 1 && (previous == "{" || previous == ","))
            key_text = ""
            key_was_escaped = 0
            continue
        }
        if (character == "{" || character == "[") {
            depth++
            previous = character
            continue
        }
        if (character == "}" || character == "]") {
            depth--
            previous = character
            continue
        }
        previous = character
    }
}
