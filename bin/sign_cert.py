from pyasn1_modules import pem, rfc2437, rfc2459
from pyasn1.codec.der import decoder, encoder
from hashlib import sha256
import os
import binascii
import argparse
import sys


#Usage: name_certificate.pem signature_filename
if sys.argc < 3:
    print("Usage: " + sys.argv[0] + " name_cert.pem and signature_filename")

ubstrate = pem.readPemFromFile(open(sys.argv[1])) # Read the certificate
certType = rfc2459.Certificate()
cert = decoder.decode(substrate, asn1Spec = certType)[0] #Extract the der format

# Add new signature
#os.system("openssl dgst -sha256 -sign privkey_root.pem new_admin_dump.der > new_admin_sign.der")
f = open(sys.argv[2], "rb")
sig = f.read()
sig = int(binascii.hexlify(sig), 16)
cert.setComponentByName("signatureValue", "00"+bin(sig)[2:])

#Store the new Certificate
f = open("new_cert.der", "wb")
f.write(encoder.encode(cert))
f.close()
# Rember to convert in pem after
