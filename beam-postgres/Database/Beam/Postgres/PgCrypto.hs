module Database.Beam.Postgres.PgCrypto
  ( PgCrypto(..) ) where

import Database.Beam
import Database.Beam.Backend.SQL

import Database.Beam.Postgres.Syntax
import Database.Beam.Postgres.Extensions

import Data.Text (Text)
import Data.ByteString (ByteString)
import Data.Vector (Vector)
import Data.UUID (UUID)

type PgExpr ctxt s = QGenExpr ctxt PgExpressionSyntax s

type family LiftPg ctxt s fn where
  LiftPg ctxt s (Maybe a -> b) = Maybe (PgExpr ctxt s a) -> LiftPg ctxt s b
  LiftPg ctxt s (a -> b) = PgExpr ctxt s a -> LiftPg ctxt s b
  LiftPg ctxt s a = PgExpr ctxt s a

data PgCrypto
  = PgCrypto
  { pgCryptoDigestText ::
      forall ctxt s. LiftPg ctxt s (Text -> Text -> ByteString)
  , pgCryptoDigestBytes ::
      forall ctxt s. LiftPg ctxt s (ByteString -> Text -> ByteString)
  , pgCryptoHmacText ::
      forall ctxt s. LiftPg ctxt s (Text -> Text -> Text -> ByteString)
  , pgCryptoHmacBytes ::
      forall ctxt s. LiftPg ctxt s (ByteString -> Text -> Text -> ByteString)
  , pgCryptoCrypt ::
      forall ctxt s. LiftPg ctxt s (Text -> Text -> Text)
  , pgCryptoGenSalt ::
      forall ctxt s. LiftPg ctxt s (Text -> Maybe Int -> Text)

  -- Pgp functions
  , pgCryptoPgpSymEncrypt ::
      forall ctxt s. LiftPg ctxt s (Text -> Text -> Maybe Text -> ByteString)
  , pgCryptoPgpSymEncryptBytea ::
      forall ctxt s. LiftPg ctxt s (ByteString -> Text -> Maybe Text -> ByteString)

  , pgCryptoPgpSymDecrypt ::
      forall ctxt s. LiftPg ctxt s (ByteString -> Text -> Maybe Text -> Text)
  , pgCryptoPgpSymDecryptBytea ::
      forall ctxt s. LiftPg ctxt s (ByteString -> Text -> Maybe Text -> ByteString)

  , pgCryptoPgpPubEncrypt ::
      forall ctxt s. LiftPg ctxt s (Text -> ByteString -> Maybe Text -> ByteString)
  , pgCryptoPgpPubEncryptBytea ::
      forall ctxt s. LiftPg ctxt s (ByteString -> ByteString -> Maybe Text -> ByteString)

  , pgCryptoPgpPubDecrypt ::
      forall ctxt s. LiftPg ctxt s (ByteString -> ByteString -> Maybe Text -> Maybe Text -> Text)
  , pgCryptoPgpPubDecryptBytea ::
      forall ctxt s. LiftPg ctxt s (ByteString -> ByteString -> Maybe Text -> Maybe Text -> ByteString)

  , pgCryptoPgpKeyId ::
      forall ctxt s. LiftPg ctxt s (ByteString -> Text)

  , pgCryptoArmor ::
      forall ctxt s. PgExpr ctxt s ByteString ->
                     Maybe (PgExpr ctxt s (Vector Text), PgExpr ctxt s (Vector Text)) ->
                     PgExpr ctxt s Text
  , pgCryptoDearmor ::
      forall ctxt s. LiftPg ctxt s (Text -> ByteString)

-- TODO setof
--  , pgCryptoPgpArmorHeaders ::
--      forall ctxt s. LiftPg ctxt s (Text -> )

  , pgCryptoGenRandomBytes ::
      forall ctxt s i. Integral i => PgExpr ctxt s i -> PgExpr ctxt s ByteString
  , pgCryptoGenRandomUUID ::
      forall ctxt s. PgExpr ctxt s UUID
  }

funcE :: IsSql99ExpressionSyntax expr => Text -> [expr] -> expr
funcE nm args = functionCallE (fieldE (unqualifiedField nm)) args

instance IsPgExtension PgCrypto where
  pgExtensionName _ = "pgcrypto"
  pgExtensionBuild = PgCrypto {
    pgCryptoDigestText  =
        \(QExpr data_) (QExpr type_) -> QExpr $ funcE "digest" [data_, type_],
    pgCryptoDigestBytes =
        \(QExpr data_) (QExpr type_) -> QExpr $ funcE "digest" [data_, type_],
    pgCryptoHmacText =
        \(QExpr data_) (QExpr key) (QExpr type_) -> QExpr $ funcE "hmac" [data_, key, type_],
    pgCryptoHmacBytes =
        \(QExpr data_) (QExpr key) (QExpr type_) -> QExpr $ funcE "hmac" [data_, key, type_],

    pgCryptoCrypt =
        \(QExpr pw) (QExpr salt) ->
           QExpr $funcE "crypt" [pw, salt],
    pgCryptoGenSalt =
        \(QExpr text) iterCount ->
           QExpr $
           funcE "gen_salt" ([text] ++ maybe [] (\(QExpr iterCount') -> [iterCount']) iterCount),

    pgCryptoPgpSymEncrypt =
        \(QExpr data_) (QExpr pw) options ->
           QExpr $
           funcE "pgp_sym_encrypt" ([data_, pw] ++ maybe [] (\(QExpr options') -> [options']) options),
    pgCryptoPgpSymEncryptBytea =
        \(QExpr data_) (QExpr pw) options ->
           QExpr $
           funcE "pgp_sym_encrypt_bytea" ([data_, pw] ++ maybe [] (\(QExpr options') -> [options']) options),

    pgCryptoPgpSymDecrypt =
        \(QExpr data_) (QExpr pw) options ->
             QExpr $
             funcE "pgp_sym_decrypt" ([data_, pw] ++ maybe [] (\(QExpr options') -> [options']) options),
    pgCryptoPgpSymDecryptBytea =
        \(QExpr data_) (QExpr pw) options ->
             QExpr $
             funcE "pgp_sym_decrypt_bytea" ([data_, pw] ++ maybe [] (\(QExpr options') -> [options']) options),

    pgCryptoPgpPubEncrypt =
        \(QExpr data_) (QExpr key) options ->
             QExpr $
             funcE "pgp_pub_encrypt" ([data_, key] ++ maybe [] (\(QExpr options') -> [options']) options),
    pgCryptoPgpPubEncryptBytea =
        \(QExpr data_) (QExpr key) options ->
             QExpr $
             funcE "pgp_pub_encrypt_bytea" ([data_, key] ++ maybe [] (\(QExpr options') -> [options']) options),

    pgCryptoPgpPubDecrypt =
        \(QExpr msg) (QExpr key) pw options ->
              QExpr $
              funcE "pgp_pub_decrypt"
                  ( [msg, key] ++
                    case (pw, options) of
                      (Nothing, Nothing) -> []
                      (Just (QExpr pw'), Nothing) -> [pw']
                      (Nothing, Just (QExpr options')) -> [ valueE (sqlValueSyntax ("" :: String))
                                                          , options' ]
                      (Just (QExpr pw'), Just (QExpr options')) -> [pw', options'] ),
    pgCryptoPgpPubDecryptBytea =
        \(QExpr msg) (QExpr key) pw options ->
              QExpr $
              funcE "pgp_pub_decrypt_bytea"
                  ( [msg, key] ++
                    case (pw, options) of
                      (Nothing, Nothing) -> []
                      (Just (QExpr pw'), Nothing) -> [pw']
                      (Nothing, Just (QExpr options')) -> [ valueE (sqlValueSyntax ("" :: String))
                                                          , options' ]
                      (Just (QExpr pw'), Just (QExpr options')) -> [pw', options'] ),

    pgCryptoPgpKeyId =
        \(QExpr data_) -> QExpr $ funcE "pgp_key_id" [data_],

    pgCryptoArmor =
        \(QExpr data_) keysData ->
            QExpr $ funcE "armor" $
            [data_] ++
            case keysData of
              Nothing -> []
              Just (QExpr keys, QExpr values) ->
                [keys, values],
    pgCryptoDearmor =
        \(QExpr data_) -> QExpr $ funcE "dearmor" [data_],

    pgCryptoGenRandomBytes =
        \(QExpr count) ->
            QExpr $ funcE "gen_random_bytes" [count],
    pgCryptoGenRandomUUID =
         QExpr $ funcE "gen_random_uuid" []
    }