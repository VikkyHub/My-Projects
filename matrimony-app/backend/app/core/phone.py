import phonenumbers


class InvalidPhone(ValueError):
    pass


def normalize_phone(raw: str, default_region: str = "IN") -> str:
    """Return E.164 (+919876543210). Raises InvalidPhone."""
    try:
        num = phonenumbers.parse(raw, default_region)
    except phonenumbers.NumberParseException as e:
        raise InvalidPhone("Invalid phone number") from e
    if not phonenumbers.is_valid_number(num):
        raise InvalidPhone("Invalid phone number")
    if phonenumbers.number_type(num) not in (
        phonenumbers.PhoneNumberType.MOBILE,
        phonenumbers.PhoneNumberType.FIXED_LINE_OR_MOBILE,
    ):
        raise InvalidPhone("Please use a mobile number")
    return phonenumbers.format_number(num, phonenumbers.PhoneNumberFormat.E164)
