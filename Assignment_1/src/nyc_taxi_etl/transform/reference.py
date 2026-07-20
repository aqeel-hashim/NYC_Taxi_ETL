"""Known TLC reference values for Yellow Taxi dimensions.

Derived from official TLC data dictionary:
https://www.nyc.gov/assets/tlc/downloads/pdf/data_dictionary_trip_records_yellow.pdf
"""

VENDOR_LOOKUP: dict[int, str] = {
    0: "Unknown",
    1: "Creative Mobile Technologies",
    2: "VeriFone Inc",
}

PAYMENT_TYPE_LOOKUP: dict[int, str] = {
    0: "Unknown",
    1: "Credit card",
    2: "Cash",
    3: "No charge",
    4: "Dispute",
    5: "Unknown",
    6: "Voided trip",
}

RATE_CODE_LOOKUP: dict[int, str] = {
    0: "Unknown",
    1: "Standard rate",
    2: "JFK",
    3: "Newark",
    4: "Nassau or Westchester",
    5: "Negotiated fare",
    6: "Group ride",
}
