module Botan.Prelude where

import Prelude

import Control.Monad

import Data.ByteString (ByteString)
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Internal as ByteString
import qualified Data.ByteString.Unsafe as ByteString

import Data.Text (Text)
import qualified Data.Text.Encoding as Text

import System.IO

import Foreign.C.String
import Foreign.C.Types
import Foreign.ForeignPtr
import Foreign.Ptr

-- Because:
--  https://github.com/haskell/text/issues/239
-- Is still an issue
peekCStringText :: CString -> IO Text
peekCStringText cs = do
    bs <- ByteString.unsafePackCString cs
    return $! Text.decodeUtf8 bs

-- A cheap knockoff of ByteArray.alloc / allocRet
-- We'll make this safer in the future
-- NOTE: THIS IS NOT LIKE Foriegn.Marshal.Alloc.allocaBytes, though it is close
--  Instead of returning the thing, we always return a bytestring.
--  Also, allocaBytes frees the memory after, but this is a malloc freed on garbage collect.
-- I basically ripped the relevant bits from ByteArray for ease of continuity
allocBytes :: Int -> (Ptr p -> IO ()) -> IO ByteString
allocBytes sz f
    | sz < 0    = allocBytes 0 f
    | otherwise = do
        fptr <- ByteString.mallocByteString sz
        _ <- withForeignPtr fptr (f . castPtr)
        return $ ByteString.PS fptr 0 sz

asCString :: ByteString -> (Ptr CChar -> IO a) -> IO a
asCString = ByteString.useAsCString

asCStringLen :: ByteString -> (Ptr CChar -> CSize -> IO a) -> IO a
asCStringLen bs f = ByteString.useAsCStringLen bs (\ (ptr,len) -> f ptr (fromIntegral len))

asBytes :: ByteString -> (Ptr byte -> IO a) -> IO a
asBytes bs f = asBytesLen bs (\ ptr _ -> f ptr) 

unsafeAsBytes :: ByteString -> (Ptr byte -> IO a) -> IO a
unsafeAsBytes bs f = unsafeAsBytesLen bs (\ ptr _ -> f ptr) 

asBytesLen :: ByteString -> (Ptr byte -> CSize -> IO a) -> IO a
asBytesLen bs f = ByteString.useAsCStringLen bs (\ (ptr,len) -> f (castPtr ptr) (fromIntegral len))

unsafeAsBytesLen :: ByteString -> (Ptr byte -> CSize -> IO a) -> IO a
unsafeAsBytesLen bs f = ByteString.unsafeUseAsCStringLen bs (\ (ptr,len) -> f (castPtr ptr) (fromIntegral len))
