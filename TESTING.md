# Backend testing

There are two test suites:

```text
tests/                         main cloud backend
communication_backend/tests/   aircraft communication backend
```

Install dependencies for the relevant backend and run:

```bash
pytest -q
```

The communication backend tests cover:

- Valid and invalid request status transitions
- Health and session bootstrap
- Passenger and crew pairing
- Passenger-to-crew request delivery
- Duplicate request idempotency
- Request ownership isolation
- Missing authentication
- Invalid crew pairing
- Event replay

The main backend tests cover:

- Registration, login, and profile access
- Invalid credentials and malformed requests
- Duplicate email registration
- Missing authentication
- Empty booking/model catalog responses
- Partner API-key enforcement
- Required idempotency headers
- Idempotent booking synchronization

Both suites have been executed successfully in the project-local UV environment. The tests currently emit a Starlette/httpx deprecation warning from the installed test-client stack; it does not affect test results.
