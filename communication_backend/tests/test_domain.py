import pytest

from app.domain import RequestStatus, validate_transition


def test_valid_request_transitions():
    validate_transition(RequestStatus.CREATED, RequestStatus.ACKNOWLEDGED)
    validate_transition(RequestStatus.ACKNOWLEDGED, RequestStatus.IN_PROGRESS)
    validate_transition(RequestStatus.IN_PROGRESS, RequestStatus.FULFILLED)


@pytest.mark.parametrize(
    ("current", "target"),
    [
        (RequestStatus.CREATED, RequestStatus.FULFILLED),
        (RequestStatus.FULFILLED, RequestStatus.CREATED),
        (RequestStatus.CANCELLED, RequestStatus.ACKNOWLEDGED),
        (RequestStatus.EXPIRED, RequestStatus.IN_PROGRESS),
    ],
)
def test_invalid_request_transitions_are_rejected(current, target):
    with pytest.raises(ValueError):
        validate_transition(current, target)


def test_unknown_status_is_rejected():
    with pytest.raises(ValueError):
        validate_transition("unknown", "created")
