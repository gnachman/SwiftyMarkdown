# Invalid Table Test

This tests the case where a line looks like a table header but the next line is not a separator.

## Case 1: Pipe line followed by regular text

| This looks like a header |
This is not a separator, just regular text.

## Case 2: Pipe line followed by another pipe line (no separator between)

| First header |
| Second header |
|-------------|
| Body row |

## Case 3: Pipe line followed by empty line

| Header line |

Then some text after.

## Case 4: Just a pipe line alone at end of file

| Orphan header |
