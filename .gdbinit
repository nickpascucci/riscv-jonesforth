target remote localhost:1234

tui enable
tui reg general

set logging enabled

source .gdbforth.py
source .gdbmacros
source .gdbbreaks
