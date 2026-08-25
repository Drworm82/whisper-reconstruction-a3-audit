# Word model definition
#
# The Word object is constructed inline within Build-WhisperWords.ps1
# as a PSCustomObject with the following properties:
#
#   Text   - The reconstructed word text
#   Key    - Lowercase alphanumeric key for comparison
#   From   - Start time (from first token)
#   To     - End time (from last token)
#   Tokens - Array of source tokens
#   Id     - Unique identifier in the format "$WindowIndex-$wordIndex"
#
# No separate class or type definition is required.
