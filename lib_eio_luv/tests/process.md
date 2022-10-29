# Set up the test environment

```ocaml
# #require "eio_luv";;
# open Eio.Std;;
# open Eio;;
# module Process = Eio_luv.Low_level.Process;;
module Process = Eio_luv.Low_level.Process
```

A helper function for reading all of the bytes from a handle.

```ocaml
let read_all handle buf =
    let rec read acc =
      try 
        let i = Eio_luv.Low_level.Stream.read_into handle buf in
        read (acc + i)
      with End_of_file -> acc
    in read 0
```

A simple `echo hello` process redirects to stdout.

```ocaml
# Eio_luv.run @@ fun _env ->
  Switch.run @@ fun sw ->
  let redirect = Process.[
    inherit_fd ~fd:Luv.Process.stdout ~from_parent_fd:Luv.Process.stdout ()
  ] in
  let t = Process.spawn ~redirect "echo" [ "echo"; "hello" ] in
  Process.await_exit t;;
hello
- : int * int64 = (0, 0L)
```

Using a pipe to redirect output to a buffer.

```ocaml
# Eio_luv.run @@ fun _env ->
  Switch.run @@ fun sw ->
  let parent_pipe = Eio_luv.Low_level.Pipe.init () in
  let handle = Eio_luv.Low_level.Pipe.to_handle ~sw parent_pipe in
  let buf = Luv.Buffer.create 32 in 
  let redirect = Eio_luv.Low_level.Process.[
    to_parent_pipe ~fd:Luv.Process.stdout ~parent_pipe:parent_pipe ()
  ] in
  let t = Process.spawn ~redirect "echo" [ "echo"; "Hello,"; "World!" ] in
  let _ = Process.await_exit t in
  let read = read_all handle buf in
  Luv.Buffer.to_string (Luv.Buffer.sub buf ~offset:0 ~length:read);;
- : string = "Hello, World!\n"
```

Writing to stdin of a process works.

```ocaml
# Eio_luv.run @@ fun _env ->
  Switch.run @@ fun sw ->
  let parent_pipe = Eio_luv.Low_level.Pipe.init () in
  let handle = Eio_luv.Low_level.Pipe.to_handle ~sw parent_pipe in
  let bufs = [ Luv.Buffer.from_string "Hello!" ] in 
  let redirect = Eio_luv.Low_level.Process.[
    inherit_fd ~fd:Luv.Process.stdout ~from_parent_fd:Luv.Process.stdout ();
    to_parent_pipe ~fd:Luv.Process.stdin ~parent_pipe:parent_pipe ()
  ] in
  let t = Process.spawn ~redirect "head" [ "head" ] in
  let () = Eio_luv.Low_level.Stream.write handle bufs in
  Eio_luv.Low_level.Handle.close handle;
  Process.await_exit t;;
Hello!
- : int * int64 = (0, 0L)
```

Stopping a process works.

```ocaml
# Eio_luv.run @@ fun _env ->
  Switch.run @@ fun sw ->
  let redirect = Process.[
    inherit_fd ~fd:Luv.Process.stdout ~from_parent_fd:Luv.Process.stdout ()
  ] in
  let t = Process.spawn ~redirect "sleep" [ "sleep"; "10" ] in
  Process.stop t;
  Process.await_exit t;;
- : int * int64 = (9, 0L)
```
