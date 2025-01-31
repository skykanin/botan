module Botan.Random where

import Prelude

import Control.Monad

import Data.ByteString (ByteString)
import qualified Data.ByteString as ByteString

import Data.Word

import System.IO

import Foreign.C.String
import Foreign.C.Types
import Foreign.ForeignPtr
import Foreign.Marshal.Alloc
import Foreign.Ptr
import Foreign.Storable

import Botan.Error
import Botan.Make
import Botan.Prelude

-- NOTE: Went with `Random` nomenclature rather than `RNG` because oof.

-- TODO: Make this use the new `Botan.Make` functions

data RandomStruct
type RandomPtr = Ptr RandomStruct

newtype Random = MkRandom { getRandomForeignPtr :: ForeignPtr RandomStruct }

withRandomPtr :: Random -> (RandomPtr -> IO a) -> IO a
withRandomPtr = withForeignPtr . getRandomForeignPtr

-- TODO: Later, higher-level
-- data RandomType
--     = System
--     | User
--     | UserThreadsafe
--     | Rdrand    -- NOTE: gives -40 (NotImplementedException) on my machine

-- randomTypeName :: RandomType -> ByteString
-- randomTypeName System           = "system"
-- randomTypeName User             = "user"
-- randomTypeName UserThreadsafe   = "user-threadsafe"
-- randomTypeName Rdrand           = "rdrand"

-- randomInitType :: RandomType -> IO Random
-- randomInitType = randomInitName . randomTypeName

type RandomType = ByteString

pattern BOTAN_RANDOM_TYPE_SYSTEM            = "system"          :: RandomType
pattern BOTAN_RANDOM_TYPE_USER              = "user"            :: RandomType
pattern BOTAN_RANDOM_TYPE_USER_THREADSAFE   = "user-threadsafe" :: RandomType
pattern BOTAN_RANDOM_TYPE_RDRAND            = "rdrand"          :: RandomType

-- /**
-- * Initialize a random number generator object
-- * @param rng rng object
-- * @param rng_type type of the rng, possible values:
-- *    "system": system Random
-- *    "user": userspace Random
-- *    "user-threadsafe": userspace Random, with internal locking
-- *    "rdrand": directly read RDRAND
-- * Set rng_type to null to let the library choose some default.
-- */
-- BOTAN_PUBLIC_API(2,0) int botan_rng_init(botan_rng_t* rng, const char* rng_type);
foreign import ccall unsafe botan_rng_init :: Ptr RandomPtr -> Ptr CChar -> IO BotanErrorCode
-- NOTE: Inconsistincies in init process - other objects accept a ptr + len
--  I presume that it expects a null-terminated C-String.

randomInit :: ByteString -> IO Random
randomInit name = do
    alloca $ \ outPtr -> do
        asCString name $ \ namePtr -> do 
            throwBotanIfNegative_ $ botan_rng_init outPtr namePtr
        out <- peek outPtr
        macForeignPtr <- newForeignPtr botan_rng_destroy out
        return $ MkRandom macForeignPtr

withRandom :: ByteString -> (Random -> IO a) -> IO a
withRandom = mkWithTemp1 randomInit randomDestroy

-- /**
-- * Initialize a custom random number generator from a set of callback functions
-- * @param rng_out rng object to create
-- * @param rng_name name of the rng
-- * @param context An application-specific context passed to the callback functions
-- * @param get_cb Callback for getting random bytes from the rng, return 0 for success
-- * @param add_entropy_cb Callback for adding entropy to the rng, return 0 for success, may be NULL
-- * @param destroy_cb Callback called when rng is destroyed, may be NULL
-- */
-- BOTAN_FFI_EXPORT(3, 0)
-- int botan_rng_init_custom(botan_rng_t* rng_out,
--                           const char* rng_name,
--                           void* context,
--                           int (*get_cb)(void* context, uint8_t* out, size_t out_len),
--                           int (*add_entropy_cb)(void* context, const uint8_t input[], size_t length),
--                           void (*destroy_cb)(void* context));
-- TODO: With / after higher-level interfaces.

-- /**
-- * Frees all resources of the random number generator object
-- * @param rng rng object
-- * @return 0 if success, error if invalid object handle
-- */
-- BOTAN_PUBLIC_API(2,0) int botan_rng_destroy(botan_rng_t rng);
foreign import ccall unsafe "&botan_rng_destroy" botan_rng_destroy :: FinalizerPtr RandomStruct

randomDestroy :: Random -> IO ()
randomDestroy random = finalizeForeignPtr (getRandomForeignPtr random)

-- /**
-- * Get random bytes from a random number generator
-- * @param rng rng object
-- * @param out output buffer of size out_len
-- * @param out_len number of requested bytes
-- * @return 0 on success, negative on failure
-- */
-- BOTAN_PUBLIC_API(2,0) int botan_rng_get(botan_rng_t rng, uint8_t* out, size_t out_len);
foreign import ccall unsafe botan_rng_get :: RandomPtr -> Ptr Word8 -> CSize -> IO BotanErrorCode

randomGet :: Int -> Random -> IO ByteString
randomGet len random = do
    withRandomPtr random $ \ randomPtr -> do
        bytes <- allocBytes len $ \ bytesPtr -> do
            throwBotanIfNegative_ $ botan_rng_get randomPtr bytesPtr (fromIntegral len)
        return bytes

-- /**
-- * Get random bytes from system random number generator
-- * @param out output buffer of size out_len
-- * @param out_len number of requested bytes
-- * @return 0 on success, negative on failure
-- */
-- BOTAN_PUBLIC_API(3,0) int botan_system_rng_get(uint8_t* out, size_t out_len);
foreign import ccall unsafe botan_system_rng_get :: Ptr Word8 -> CSize -> IO BotanErrorCode

systemRandomGet :: Int -> IO ByteString
systemRandomGet len = allocBytes len $ \ bytesPtr -> do
    throwBotanIfNegative_ $ botan_system_rng_get bytesPtr (fromIntegral len)

-- /**
-- * Reseed a random number generator
-- * Uses the System_RNG as a seed generator.
-- *
-- * @param rng rng object
-- * @param bits number of bits to reseed with
-- * @return 0 on success, a negative value on failure
-- */
-- BOTAN_PUBLIC_API(2,0) int botan_rng_reseed(botan_rng_t rng, size_t bits);
foreign import ccall unsafe botan_rng_reseed :: RandomPtr -> CSize -> IO BotanErrorCode

randomReseed :: Random -> Int -> IO ()
randomReseed random bits = do
    withRandomPtr random $ \ randomPtr -> do
        throwBotanIfNegative_ $ botan_rng_reseed randomPtr (fromIntegral bits)

-- /**
-- * Reseed a random number generator
-- *
-- * @param rng rng object
-- * @param source_rng the rng that will be read from
-- * @param bits number of bits to reseed with
-- * @return 0 on success, a negative value on failure
-- */
-- BOTAN_PUBLIC_API(2,8) int botan_rng_reseed_from_rng(botan_rng_t rng,
--                                                     botan_rng_t source_rng,
--                                                     size_t bits);
foreign import ccall unsafe botan_rng_reseed_from_rng :: RandomPtr -> RandomPtr -> CSize -> IO BotanErrorCode

randomReseedFromRandom :: Random -> Random -> Int -> IO ()
randomReseedFromRandom random source bits = do
    withRandomPtr random $ \ randomPtr -> do
        withRandomPtr source $ \ sourcePtr -> do
            throwBotanIfNegative_ $ botan_rng_reseed_from_rng randomPtr sourcePtr (fromIntegral bits)

-- /**
-- * Add some seed material to a random number generator
-- *
-- * @param rng rng object
-- * @param entropy the data to add
-- * @param entropy_len length of entropy buffer
-- * @return 0 on success, a negative value on failure
-- */
-- BOTAN_PUBLIC_API(2,8) int botan_rng_add_entropy(botan_rng_t rng,
--                                                 const uint8_t* entropy,
--                                                 size_t entropy_len);
foreign import ccall unsafe botan_rng_add_entropy :: RandomPtr -> Ptr Word8 -> CSize -> IO BotanErrorCode

randomAddEntropy :: Random -> ByteString -> IO ()
randomAddEntropy random bytes = do
    withRandomPtr random $ \ randomPtr -> do
        asBytesLen bytes $ \ bytesPtr bytesLen -> do
            throwBotanIfNegative_ $ botan_rng_add_entropy randomPtr bytesPtr bytesLen
