defmodule AshPostgres.ResourceGenerator.SensitiveData do
  @moduledoc false
  # I got this from ChatGPT, but this is a best effort transformation
  # anyway.
  @sensitive_patterns [
    # Password-related
    ~r/password/i,
    ~r/passwd/i,
    ~r/pass/i,
    ~r/pwd/i,
    ~r/hash(ed)?(_password)?/i,

    # Authentication-related
    ~r/auth(_key)?/i,
    ~r/token/i,
    ~r/secret(_key)?/i,
    ~r/api_key/i,

    # Personal Information
    ~r/ssn/i,
    ~r/social(_security)?(_number)?/i,
    ~r/(credit_?card|cc)(_number)?/i,
    ~r/passport(_number)?/i,
    ~r/driver_?licen(s|c)e(_number)?/i,
    ~r/national_id/i,

    # Financial Information
    ~r/account(_number)?/i,
    ~r/routing(_number)?/i,
    ~r/iban/i,
    ~r/swift(_code)?/i,
    ~r/tax_id/i,

    # Contact Information
    ~r/phone(_number)?/i,
    ~r/email(_address)?/i,
    ~r/address/i,

    # Health Information
    ~r/medical(_record)?/i,
    ~r/health(_data)?/i,
    ~r/diagnosis/i,
    ~r/treatment/i,

    # Biometric Data
    ~r/fingerprint/i,
    ~r/retina_scan/i,
    ~r/face_id/i,
    ~r/dna/i,

    # Encrypted or Encoded Data
    ~r/encrypt(ed)?/i,
    ~r/encoded/i,
    ~r/cipher/i,

    # Other Potentially Sensitive Data
    ~r/private(_key)?/i,
    ~r/confidential/i,
    ~r/restricted/i,
    ~r/sensitive/i,

    # General patterns
    ~r/.*_salt/i,
    ~r/.*_secret/i,
    ~r/.*_key/i,
    ~r/.*_token/i
  ]

  def sensitive?(column_name) do
    Enum.any?(@sensitive_patterns, fn pattern ->
      Regex.match?(pattern, column_name)
    end)
  end
end
