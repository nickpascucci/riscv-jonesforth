import pexpect
import pytest
import sys

@pytest.fixture()
def forth():
    print("setup")
    child = pexpect.spawn("make simulate", timeout=2)
    child.logfile = sys.stdout.buffer
    child.expect("jonesforth.elf")
    yield child
    child.terminate(force=True)
    print("teardown")

PRINT_RESULT = "48 + EMIT"

def execute(forth, input):
    forth.sendline(input)
    forth.sendline(PRINT_RESULT)
    forth.expect("\r\n")

def assert_output(forth, out):
    try:
        forth.expect(out)
    except:
        raise AssertionError(f"Expected '{out}', got '{forth.before.decode('ascii')}'")

cases = [
    ("1", "1"),
    ("1 2", "2"),

    ("1 2 DROP", "1"),

    ("1 2 SWAP", "1"),
    ("1 2 SWAP DROP", "2"),

    ("1 2 OVER", "1"),
    ("1 2 OVER DROP", "2"),
    ("1 2 OVER DROP DROP", "1"),

    ("1 2 3 ROT", "1"),
    ("1 2 3 ROT DROP", "3"),
    ("1 2 3 ROT DROP DROP", "2"),

    ("1 2 3 -ROT", "2"),
    ("1 2 3 -ROT DROP", "1"),
    ("1 2 3 -ROT DROP DROP", "3"),

    ("1 2 3 2DROP", "1"),

    ("1 2 2DUP", "2"),
    ("1 2 2DUP DROP", "1"),

    ("1 2 3 4 2SWAP", "2"),
    ("1 2 3 4 2SWAP DROP", "1"),
    ("1 2 3 4 2SWAP 2DROP", "4"),
    ("1 2 3 4 2SWAP 2DROP DROP", "3"),

    ("1 2 ?DUP", "2"),
    ("1 2 ?DUP DROP", "2"),
    ("1 2 ?DUP 2DROP", "1"),
    ("1 0 ?DUP", "0"),
    ("1 0 ?DUP DROP", "1"),

    ("1 1+", "2"),
    ("-1 1+", "0"),

    ("2 1-", "1"),

    ("1 4+", "5"),
    ("-1 4+", "3"),

    ("5 4-", "1"),

    ("1 1 +", "2"),

    ("2 1 -", "1"),

    ("2 3 *", "6"),

    ("7 3 /MOD", "2"),
    ("7 3 /MOD DROP", "1"),

    ("1 1 =", "1"),
    ("1 2 =", "0"),

    ("1 1 <>", "0"),
    ("1 2 <>", "1"),

    ("1 2 <", "1"),
    ("2 1 <", "0"),
    ("2 2 <", "0"),

    ("1 2 >", "0"),
    ("2 1 >", "1"),
    ("2 2 >", "0"),

    ("1 2 >=", "0"),
    ("2 2 >=", "1"),
    ("2 1 >=", "1"),

    ("1 2 <=", "1"),
    ("2 2 <=", "1"),
    ("2 1 <=", "0"),

    ("1 0=", "0"),
    ("0 0=", "1"),

    ("1 0<>", "1"),
    ("0 0<>", "0"),

    ("-1 0<", "1"),
    ("0 0<", "0"),
    ("1 0<", "0"),

    ("-1 0>", "0"),
    ("0 0>", "0"),
    ("1 0>", "1"),

    ("-1 0<=", "1"),
    ("0 0<=", "1"),
    ("1 0<=", "0"),

    ("-1 0>=", "0"),
    ("0 0>=", "1"),
    ("1 0>=", "1"),

    ("0 0 AND", "0"),
    ("1 0 AND", "0"),
    ("0 1 AND", "0"),
    ("1 1 AND", "1"),

    ("0 0 OR", "0"),
    ("1 0 OR", "1"),
    ("0 1 OR", "1"),
    ("1 1 OR", "1"),

    ("0 0 XOR", "0"),
    ("1 0 XOR", "1"),
    ("0 1 XOR", "1"),
    ("1 1 XOR", "0"),

    ("0 INVERT", "/"),
]

@pytest.mark.parametrize("input,output", cases)
def test_expression(forth, input, output):
    execute(forth, input)
    assert_output(forth, output)
