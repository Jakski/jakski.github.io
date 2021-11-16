After discovering Neovim's remote plugin interface I decided to give it a try
and develop some Python-hosted plugins. While I like the idea of moving plugin's
logic from Vim script to external language-agnostic services, I've already
stumbled upon not so trivial problems with debugging inter-process
communication.

# Scenario

So I launched Neovim hoping to see Python host update syntax highlight in my
editor, but then this showed up:

```
E475: Invalid argument: Channel doesn't exist
```

# Debbuging with documented methods

Pynvim has pretty good documentation, including debugging
[steps](https://pynvim.readthedocs.io/en/latest/development.html). Let's see
what I can get after launching Neovim with debugging flags for Python-host:

```
$ NVIM_PYTHON_LOG_FILE=logfile NVIM_PYTHON_LOG_LEVEL=DEBUG nvim
```

Now I can get trace from file `logfile_py3_rplugin` after error occurs:

```
2019-02-09 20:33:30,425 [DEBUG @ msgpack_stream.py:_on_data:61] 31297 - received message: [2, b'nvim_error_event', [1, b'Message is not an array']]
...
...
...
2019-02-09 20:33:30,466 [ERROR @ base_events.py:default_exception_handler:1608] 31297 - Exception in callback _UnixWritePipeTransport._call_connection_lost(None)
handle: <Handle _UnixWritePipeTransport._call_connection_lost(None)>
BrokenPipeError: [Errno 32] Broken pipe

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
 File "/usr/lib/python3.7/asyncio/events.py", line 88, in _run
   self._context.run(self._callback, *self._args)
 File "/usr/lib/python3.7/asyncio/unix_events.py", line 744, in _call_connection_lost
   self._pipe.close()
BrokenPipeError: [Errno 32] Broken pipe
```

Ok, so Python-host dies for some reason and it seems it sends to Neovim some
malformed messages, but I can't find out what's being actually sent.

# Debugging by tracing system calls

Before reading this part you must understand how Python-host gets started and
communicates with editor. Remote plugins take more resources than Vim scripts,
so Neovim tries to use them only when necessary. That's the reason you have to
run *:UpdateRemotePlugins*, before using any of them. *:UpdateRemotePlugins*
creates sort of a mapping between editor actions and remote procedure calls.
Every time user triggers RPC, Neovim starts plugin host if it's not yet running,
and forwards messages.

Plugin hosts are just Neovim's subprocesses communicating via standard
input/output. You can see it by triggering remote plugin and running *ps -ef
--forest*:

```
jakub    20904  2164  0 13:47 pts/5    00:00:00  |   \_ -bash
jakub    29952 20904  0 19:53 pts/5    00:00:03  |   |   \_ vim
jakub    29989 29952  0 19:53 ?        00:00:01  |   |       \_ python3 -c import sys; sys.path.remove(""); import neovim; neovim.start_host() /home/jakub/.vim/plugged/vim-yaml/rplugin/python3/vim_yaml
```

I'm going to track messages sent by process 29989. Every time plugin host
communicates with Neovim it issues system call to write something to file
descriptor 1(standard output). I can spy on messages with *strace*:

```
$ strace -e write=1 -p 29989
strace: Process 31563 attached
epoll_wait(3,
```


*strace* is really verbose, so I limited it to show only writes to standard
output. Now I have to reproduce error in editor. Just before error occurs I
see:

```
write(1, "StreamStartToken 0 0 0\nDocumentS"..., 8195) = 8195
 | 00000  53 74 72 65 61 6d 53 74  61 72 74 54 6f 6b 65 6e  StreamStartToken |
 | 00010  20 30 20 30 20 30 0a 44  6f 63 75 6d 65 6e 74 53   0 0 0.DocumentS |
 | 00020  74 61 72 74 54 6f 6b 65  6e 20 30 20 30 20 33 0a  tartToken 0 0 3. |
 | 00030  42 6c 6f 63 6b 4d 61 70  70 69 6e 67 53 74 61 72  BlockMappingStar |
 | 00040  74 54 6f 6b 65 6e 20 32  20 30 20 30 0a 4b 65 79  tToken 2 0 0.Key |
...
...
...
```

This certainly doesn't look like RPC message sent by plugin host, so what's
that? It turned out to be one of my debug prints which worked fine, when I ran
tests with Tox, but caused headache for Neovim, because it's not proper msgpack
payload accepted as RPC. Removing single *print(...)* solved everything.
