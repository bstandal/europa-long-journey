import {
  createHash,
  createHmac,
  createPrivateKey,
  createPublicKey,
} from "node:crypto";

// This signing identity is reproducible test material, not a secret. It exists
// solely so the isolated development package can be rebuilt byte-for-byte.
// Release compilers and the Release app scanner reject its separate package,
// key and trust-domain identity.
const curve = Object.freeze({
  p: BigInt("0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff"),
  a: BigInt("0xffffffff00000001000000000000000000000000fffffffffffffffffffffffc"),
  n: BigInt("0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551"),
  generator: Object.freeze({
    x: BigInt("0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296"),
    y: BigInt("0x4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5"),
  }),
});

const derivationContext = Buffer.from(
  "the-long-west-vertical-slice-development-v1/reproducible-signing-material-v1",
  "utf8",
);

function modulo(value, modulus) {
  const result = value % modulus;
  return result >= 0n ? result : result + modulus;
}

function inverse(value, modulus) {
  let oldR = modulo(value, modulus);
  let r = modulus;
  let oldS = 1n;
  let s = 0n;
  while (r !== 0n) {
    const quotient = oldR / r;
    [oldR, r] = [r, oldR - quotient * r];
    [oldS, s] = [s, oldS - quotient * s];
  }
  if (oldR !== 1n) throw new Error("P-256 inverse does not exist");
  return modulo(oldS, modulus);
}

function addPoints(left, right) {
  if (left === null) return right;
  if (right === null) return left;
  if (left.x === right.x && modulo(left.y + right.y, curve.p) === 0n) return null;
  const slope = left.x === right.x && left.y === right.y
    ? modulo((3n * left.x * left.x + curve.a) * inverse(2n * left.y, curve.p), curve.p)
    : modulo((right.y - left.y) * inverse(right.x - left.x, curve.p), curve.p);
  const x = modulo(slope * slope - left.x - right.x, curve.p);
  const y = modulo(slope * (left.x - x) - left.y, curve.p);
  return { x, y };
}

function multiplyPoint(scalar, point = curve.generator) {
  let factor = scalar;
  let addend = point;
  let result = null;
  while (factor > 0n) {
    if ((factor & 1n) === 1n) result = addPoints(result, addend);
    addend = addPoints(addend, addend);
    factor >>= 1n;
  }
  if (result === null) throw new Error("P-256 scalar produced the point at infinity");
  return result;
}

function bytesToInteger(bytes) {
  const hex = Buffer.from(bytes).toString("hex");
  return hex ? BigInt(`0x${hex}`) : 0n;
}

function integerBytes(value, length = 32) {
  const hex = value.toString(16).padStart(length * 2, "0");
  return Buffer.from(hex, "hex");
}

function base64URL(value) {
  return Buffer.from(value).toString("base64url");
}

const privateScalar = modulo(
  bytesToInteger(createHash("sha256").update(derivationContext).digest()),
  curve.n - 1n,
) + 1n;
const publicPoint = multiplyPoint(privateScalar);
const privateKey = createPrivateKey({
  format: "jwk",
  key: {
    kty: "EC",
    crv: "P-256",
    x: base64URL(integerBytes(publicPoint.x)),
    y: base64URL(integerBytes(publicPoint.y)),
    d: base64URL(integerBytes(privateScalar)),
  },
});
const publicKey = createPublicKey(privateKey);

function hmac(key, ...values) {
  const instance = createHmac("sha256", key);
  for (const value of values) instance.update(value);
  return instance.digest();
}

function deterministicNonce(messageHash) {
  const scalarBytes = integerBytes(privateScalar);
  const hashScalarBytes = integerBytes(modulo(bytesToInteger(messageHash), curve.n));
  let key = Buffer.alloc(32, 0);
  let value = Buffer.alloc(32, 1);
  key = hmac(key, value, Buffer.from([0]), scalarBytes, hashScalarBytes);
  value = hmac(key, value);
  key = hmac(key, value, Buffer.from([1]), scalarBytes, hashScalarBytes);
  value = hmac(key, value);
  while (true) {
    value = hmac(key, value);
    const candidate = bytesToInteger(value);
    if (candidate > 0n && candidate < curve.n) return candidate;
    key = hmac(key, value, Buffer.from([0]));
    value = hmac(key, value);
  }
}

function derInteger(value) {
  let bytes = integerBytes(value);
  while (bytes.length > 1 && bytes[0] === 0 && (bytes[1] & 0x80) === 0) {
    bytes = bytes.subarray(1);
  }
  if ((bytes[0] & 0x80) !== 0) bytes = Buffer.concat([Buffer.from([0]), bytes]);
  return Buffer.concat([Buffer.from([0x02, bytes.length]), bytes]);
}

function derSignature(r, s) {
  const body = Buffer.concat([derInteger(r), derInteger(s)]);
  if (body.length >= 128) throw new Error("Unexpected P-256 DER signature length");
  return Buffer.concat([Buffer.from([0x30, body.length]), body]);
}

export function verticalSliceDevelopmentPublicKey() {
  return publicKey;
}

export function signVerticalSliceDevelopmentMessage(message) {
  const messageHash = createHash("sha256").update(message).digest();
  let nonce = deterministicNonce(messageHash);
  while (true) {
    const noncePoint = multiplyPoint(nonce);
    const r = modulo(noncePoint.x, curve.n);
    if (r !== 0n) {
      const z = modulo(bytesToInteger(messageHash), curve.n);
      let s = modulo(inverse(nonce, curve.n) * (z + r * privateScalar), curve.n);
      if (s !== 0n) {
        if (s > curve.n / 2n) s = curve.n - s;
        return derSignature(r, s);
      }
    }
    nonce = modulo(nonce, curve.n - 1n) + 1n;
  }
}
