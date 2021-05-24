(*
 * Copyright (C) 2020-2021 Anil Madhavapeddy
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

type t

(** Wrap [Unix.file_descr] to track whether it has been closed. *)
module FD : sig
  type t

  val is_open : t -> bool
  (** [is_open t] is [true] if {!close t} hasn't been called yet. *)

  val close : t -> unit
  (** [close t] closes [t].
      @raise Invalid_arg if [t] is already closed. *)

  val of_unix : Unix.file_descr -> t
  (** [of_unix fd] wraps [fd] as an open file descriptor.
      This is unsafe if [fd] is closed directly (before or after wrapping it). *)

  val to_unix : t -> Unix.file_descr
  (** [to_unix t] returns the wrapped descriptor.
      This allows unsafe access to the FD.
      @raise Invalid_arg if [t] is closed. *)
end

(** {1 Time functions} *)

val sleep : float -> unit
(** [sleep s] blocks until (at least) [s] seconds have passed. *)

(** {1 Memory allocation functions} *)

val alloc : unit -> Uring.Region.chunk

val free : Uring.Region.chunk -> unit

val with_chunk : (Uring.Region.chunk -> 'a) -> 'a
(** [with_chunk fn] runs [fn chunk] with a freshly allocated chunk and then frees it. *)

(** {1 File manipulation functions} *)

val openfile : string -> Unix.open_flag list -> int -> FD.t
(** Like {!Unix.open_file}. *)

val read_upto : ?file_offset:Optint.Int63.t -> FD.t -> Uring.Region.chunk -> int -> int
(** [read_upto fd chunk len] reads at most [len] bytes from [fd],
    returning as soon as some data is available.
    @param file_offset Read from the given position in [fd] (default: 0).
    @raise End_of_file Raised if all data has already been read. *)

val read_exactly : ?file_offset:Optint.Int63.t -> FD.t -> Uring.Region.chunk -> int -> unit
(** [read_exactly fd chunk len] reads exactly [len] bytes from [fd],
    performing multiple read operations if necessary.
    @param file_offset Read from the given position in [fd] (default: 0).
    @raise End_of_file Raised if the stream ends before [len] bytes have been read. *)

val write : ?file_offset:Optint.Int63.t -> FD.t -> Uring.Region.chunk -> int -> unit
(** [write fd buf len] writes exactly [len] bytes from [buf] to [fd].
    It blocks until the OS confirms the write is done,
    and resubmits automatically if the OS doesn't write all of it at once. *)

val splice : FD.t -> dst:FD.t -> len:int -> int
(** [splice src ~dst ~len] attempts to copy up to [len] bytes of data from [src] to [dst].
    @return The number of bytes copied.
    @raise End_of_file [src] is at the end of the file.
    @raise Unix.Unix_error(EINVAL, "splice", _) if splice is not supported for these FDs. *)

val await_readable : FD.t -> unit
(** [await_readable fd] blocks until [fd] is readable (or has an error). *)

val await_writable : FD.t -> unit
(** [await_writable fd] blocks until [fd] is writable (or has an error). *)

val fstat : FD.t -> Unix.stats
(** Like {!Unix.fstat}. *)

(** {1 Sockets} *)

val accept : FD.t -> (FD.t * Unix.sockaddr)
(** [accept t] blocks until a new connection is received on listening socket [t].
    It returns the new connection and the address of the connecting peer.
    The new connection has the close-on-exec flag set automatically. *)

val shutdown : FD.t -> Unix.shutdown_command -> unit
(** Like {!Unix.shutdown}. *)

(** {1 Eio API} *)

module Objects : sig
  (** [source fd] is an Eio source that reads from [fd]. *)
  class source : FD.t -> object
    inherit Eio.Source.t
    method read_into : Cstruct.t -> int
    method fd : FD.t
    method close : unit
  end

  (** [sink fd] is an Eio sink that writes to [fd]. *)
  class sink : FD.t -> object
    inherit Eio.Sink.t
    method write : #Eio.Source.t -> unit
    method fd : FD.t
    method close : unit
  end
end

val pipe : unit -> Objects.source * Objects.sink
(** [pipe ()] is a source-sink pair [(r, w)], where data written to [w] can be read from [r].
    It is implemented as a Unix pipe. *)

(** {1 Main Loop} *)

val run : ?queue_depth:int -> ?block_size:int -> (Eio.Stdenv.t -> unit) -> unit
(** FIXME queue_depth and block_size should be in a handler and not the mainloop *)