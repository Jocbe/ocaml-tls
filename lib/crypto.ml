
let (<>) = Utils.cs_append

let hmac_md5 sec = Cryptokit.(hash_string (MAC.hmac_md5 sec))
let hmac_sha sec = Cryptokit.(hash_string (MAC.hmac_sha1 sec))

let rec p_hash (hmac, hmac_n) secret seed len =
  let rec expand a to_go =
    let res = hmac secret (a ^ seed) in
    if to_go > hmac_n then
      res ^ expand (hmac secret a) (to_go - hmac_n)
    else String.sub res 0 to_go
  in
  expand (hmac secret seed) len

let halve secret =
  let len  = String.length secret in
  let half = len - len / 2 in
  String.( sub secret 0 half, sub secret (len - half) half )

let pseudo_random_function len secret label seed =
  let (s1, s2) = halve secret in
  let md5 = p_hash (hmac_md5, 16) s1 (label ^ seed) len
  and sha = p_hash (hmac_sha, 20) s2 (label ^ seed) len in
  Cryptokit.xor_string md5 0 sha 0 len ;
  sha

let generate_master_secret pre_master_secret seed =
  pseudo_random_function 48 pre_master_secret "master secret" seed

let key_block len master_secret seed =
  pseudo_random_function len master_secret "key expansion" seed

let finished master_secret label data =
  let md5 = Cryptokit.(hash_string (Hash.md5 ()) data) in
  let sha1 = Cryptokit.(hash_string (Hash.sha1 ()) data) in
  pseudo_random_function 12 master_secret label (md5 ^ sha1)

let encryptRSA key msg =
  Cryptokit.RSA.encrypt key msg

let decryptRSA key msg =
  Cryptokit.RSA.decrypt key msg

let hmac = function
  | Ciphersuite.MD5 -> hmac_md5
  | Ciphersuite.SHA -> hmac_sha
  | _               -> assert false

let signature : Ciphersuite.hash_algorithm -> string -> int64 -> Packet.content_type -> Cstruct.t -> Cstruct.t
  = fun mac secret n ty data ->
      let prefix = Cstruct.create 13 in
      let len = Cstruct.len data in
      Cstruct.BE.set_uint64 prefix 0 n;
      Cstruct.set_uint8 prefix 8 (Packet.content_type_to_int ty);
      Cstruct.set_uint8 prefix 9 3; (* version major *)
      Cstruct.set_uint8 prefix 10 1; (* version minor *)
      Cstruct.BE.set_uint16 prefix 11 len;
      let to_sign = prefix <> data in
      let ps = Cstruct.copy to_sign 0 (Cstruct.len to_sign) in
      let res = hmac mac secret ps in
      Cstruct.of_string res

(* encryption and decryption is the same, thus "crypt" *)
let crypt_stream : Cryptokit.Stream.stream_cipher -> Cstruct.t -> Cstruct.t
  = fun cipher decrypted ->
      let len = Cstruct.len decrypted in
      let encrypted = String.create len in
      let dec = Cstruct.copy decrypted 0 len in
      cipher#transform dec 0 encrypted 0 len;
      Cstruct.of_string encrypted

let pad : Ciphersuite.encryption_algorithm -> Cstruct.t -> Cstruct.t
  = fun enc data ->
  let bs = Ciphersuite.encryption_algorithm_block_size enc in
  (* 1 is the padding length, encoded as 8 bit at the end of the fragment *)
  let len = 1 + Cstruct.len data in
  (* we might want to add additional blocks of padding *)
  let padding_length = bs - (len mod bs) in
  (* 1 is again padding length field *)
  let cstruct_len = padding_length + 1 in
  let pad = Cstruct.create cstruct_len in
  for i = 0 to (cstruct_len - 1) do
    Cstruct.set_uint8 pad i padding_length
  done;
  pad

(* in: algo, secret, iv, data
   out: [padded]encrypted data, new_iv *)
let encrypt_block : Ciphersuite.encryption_algorithm -> string -> string -> Cstruct.t -> (Cstruct.t * string)
  = fun cipher sec iv data ->
      let to_encrypt = data <> (pad cipher data) in
      let cip = match cipher with
        | Ciphersuite.TRIPLE_DES_EDE_CBC ->
           let cip = new Cryptokit.Block.triple_des_encrypt sec in
           new Cryptokit.Block.cbc_encrypt ~iv:iv cip
        | _ -> assert false
      in
      let datalen = Cstruct.len to_encrypt in
      let bs = Ciphersuite.encryption_algorithm_block_size cipher in
      let blocks = datalen / bs in
      let enc = String.create (Cstruct.len to_encrypt) in
      let dat = Cstruct.copy to_encrypt 0 datalen in
      for i = 0 to (blocks - 1) do
        cip#transform dat (i * bs) enc (i * bs)
      done;
      (* last block is new iv *)
      (Cstruct.of_string enc, String.sub enc ((blocks - 1) * bs) bs)

(* in: algo, secret, iv, data
   out: [padded]decrypted data, new_iv *)
let decrypt_block : Ciphersuite.encryption_algorithm -> string -> string -> Cstruct.t -> (Cstruct.t * string)
  = fun cipher sec iv data ->
      let cip = match cipher with
        | Ciphersuite.TRIPLE_DES_EDE_CBC ->
           let cip = new Cryptokit.Block.triple_des_decrypt sec in
           new Cryptokit.Block.cbc_decrypt ~iv:iv cip
        | _ -> assert false
      in
      let datalen = Cstruct.len data in
      let bs = Ciphersuite.encryption_algorithm_block_size cipher in
      let blocks = datalen / bs in
      let dec = String.create datalen in
      let dat = Cstruct.copy data 0 datalen in
      for i = 0 to (blocks - 1) do
        cip#transform dat (i * bs) dec (i * bs)
      done;
      (* last block is new iv *)
      (Cstruct.of_string dec, String.sub dat ((blocks - 1) * bs) bs)
