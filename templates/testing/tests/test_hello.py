import testing


def test_hello(capsys):
    testing.hello()
    captured = capsys.readouterr()
    assert captured.out == "Hello from testing!\n"
    assert captured.err == ""
