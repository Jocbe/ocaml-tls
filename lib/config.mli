open Nocrypto
open Core

(** Configuration of the TLS stack *)

(** certificate chain and private key of the first certificate *)
type own_cert = Certificate.certificate list * Nocrypto.Rsa.priv

(** configuration parameters *)
type config = private {
  ciphers           : Ciphersuite.ciphersuite list ; (** ordered list (regarding preference) of supported cipher suites *)
  protocol_versions : tls_version * tls_version ; (** supported protocol versions (min, max) *)
  hashes            : Hash.hash list ; (** ordered list of supported hash algorithms (regarding preference) *)
  use_reneg         : bool ; (** endpoint should accept renegotiation requests *)
  secure_reneg      : bool ; (** other end must use secure renegotiation (RFC 5746) *)
  authenticator     : X509.Authenticator.t option ; (** optional X509 authenticator *)
  peer_name         : string option ; (** optional name of other endpoint (used for SNI RFC4366) *)
  own_certificate   : own_cert option ; (** optional certificate chain *)
} with sexp

module Ciphers : sig

  open Ciphersuite

  (** Cipher selection related utilities. *)

  val supported : ciphersuite list
  (** All the ciphers this library can use. *)

  val pfs : ciphersuite list
  (** All the PFS ciphers this library can use. *)

  val pfs_of : ciphersuite list -> ciphersuite list
  (** [pfs_of ciphers] selects only PFS ciphers. *)
end

(** [supported_hashes] is a list of supported hash algorithms by this library *)
val supported_hashes  : Hash.hash list

(** [min_dh_size] is minimal diffie hellman group size in bits (currently 512) *)
val min_dh_size : int

(** [min_rsa_key_size] is minimal RSA modulus key size in bits (currently 1024) *)
val min_rsa_key_size : int

(** opaque type of a client configuration *)
type client

(** opaque type of a server configuration *)
type server

(** [peer client name] is [client] with [name] as [peer_name] *)
val peer : client -> string -> client

(** [of_client client] is a client configuration for [client] *)
val of_client : client -> config

(** [of_server server] is a server configuration for [server] *)
val of_server : server -> config

(** [client_exn ?ciphers ?version ?hashes ?reneg ?validator ?secure_reneg] is [client] configuration with the given parameters *)
(** @raise Invalid_argument if the configuration is invalid *)
val client :
  authenticator  : X509.Authenticator.t ->
  ?ciphers       : Ciphersuite.ciphersuite list ->
  ?version       : tls_version * tls_version ->
  ?hashes        : Hash.hash list ->
  ?reneg         : bool ->
  ?secure_reneg  : bool ->
  unit -> client

(** [server_exn ?ciphers ?version ?hashes ?reneg ?certificate ?secure_reneg] is [server] configuration with the given parameters *)
(** @raise Invalid_argument if the configuration is invalid *)
val server :
  ?ciphers      : Ciphersuite.ciphersuite list ->
  ?version      : tls_version * tls_version ->
  ?hashes       : Hash.hash list ->
  ?reneg        : bool ->
  ?certificate  : own_cert ->
  ?secure_reneg : bool ->
  unit -> server
