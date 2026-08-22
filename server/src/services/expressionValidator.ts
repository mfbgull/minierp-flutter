/**
 * Expression Validator (REP-18)
 * -----------------------------
 * Validates custom-report `computedColumns[].expression` strings against a
 * safe grammar BEFORE they are interpolated into SQL:
 *
 *   expression  := term (( '+' | '-' ) term)*
 *   term        := factor (( '*' | '/' | '%' ) factor)*
 *   factor      := NUMBER | IDENT | FUNC '(' args ')' | '(' expression ')' | ('-'|'+') factor
 *   args        := expression (',' expression)*          (CAST takes a type argument)
 *
 * Allowed tokens:
 *   - numeric literals (integer/decimal)
 *   - identifiers from the report's own field list + computed-column names
 *   - functions: ROUND, ABS, COALESCE, IFNULL, MIN, MAX, CAST
 *   - operators: + - * / % and parentheses; comma for function args
 *
 * Everything else is rejected with a 400-shaped error naming the offending
 * token: string literals, semicolons, SQL comments, keywords (SELECT, CASE,
 * …), unknown functions, unknown identifiers.
 */


/** Error carrying a user-safe message; controllers map it to HTTP 400. */
export class ExpressionValidationError extends Error {
  readonly token: string;
  readonly position: number;

  constructor(token: string, position: number, message: string) {
    super(message);
    this.name = 'ExpressionValidationError';
    this.token = token;
    this.position = position;
  }
}

const ALLOWED_FUNCTIONS = new Set([
  'ROUND', 'ABS', 'COALESCE', 'IFNULL', 'MIN', 'MAX', 'CAST',
]);

type TokenType =
  | 'number' | 'ident' | 'func' | 'op' | 'lparen' | 'rparen'
  | 'comma' | 'cast-type';

interface Token {
  type: TokenType;
  value: string;
  position: number;
}

// ── Tokenizer ────────────────────────────────────────────────

function tokenize(input: string): Token[] {
  const tokens: Token[] = [];
  let i = 0;

  while (i < input.length) {
    const ch = input[i];

    // Whitespace
    if (/\s/.test(ch)) {
      i += 1;
      continue;
    }

    // String literal — always rejected (token-named error)
    if (ch === "'" || ch === '"') {
      throw new ExpressionValidationError(
        ch, i,
        `String literals are not allowed in expressions. Only numbers, report fields, arithmetic (+ - * / %), parentheses, and ROUND/ABS/COALESCE/IFNULL/MIN/MAX/CAST may be used.`
      );
    }

    // SQL comments — always rejected
    if (ch === '-' && input[i + 1] === '-') {
      throw new ExpressionValidationError('--', i, 'SQL comments are not allowed in expressions.');
    }
    if (ch === '/' && input[i + 1] === '*') {
      throw new ExpressionValidationError('/*', i, 'SQL comments are not allowed in expressions.');
    }

    // Semicolon — statement separator, always rejected
    if (ch === ';') {
      throw new ExpressionValidationError(';', i, 'Semicolons are not allowed in expressions.');
    }

    // Numbers
    if (/[0-9]/.test(ch) || (ch === '.' && /[0-9]/.test(input[i + 1] || ''))) {
      let j = i;
      while (j < input.length && /[0-9.]/.test(input[j])) j += 1;
      const value = input.slice(i, j);
      if ((value.match(/\./g) || []).length > 1) {
        throw new ExpressionValidationError(value, i, `Invalid numeric literal "${value}".`);
      }
      tokens.push({ type: 'number', value, position: i });
      i = j;
      continue;
    }

    // Identifiers / function names
    if (/[A-Za-z_]/.test(ch)) {
      let j = i;
      while (j < input.length && /[A-Za-z0-9_]/.test(input[j])) j += 1;

      // Skip whitespace to see whether a '(' follows (function call).
      let k = j;
      while (k < input.length && /\s/.test(input[k])) k += 1;

      if (input[k] === '(') {
        const name = input.slice(i, j).toUpperCase();
        if (!ALLOWED_FUNCTIONS.has(name)) {
          throw new ExpressionValidationError(
            input.slice(i, j), i,
            `Function "${input.slice(i, j)}" is not allowed. Allowed functions: ${[...ALLOWED_FUNCTIONS].join(', ')}.`
          );
        }
        tokens.push({ type: 'func', value: name, position: i });
        i = j;
        continue;
      }

      tokens.push({ type: 'ident', value: input.slice(i, j), position: i });
      i = j;
      continue;
    }

    // Operators & punctuation
    if ('+-*/%'.includes(ch)) {
      tokens.push({ type: 'op', value: ch, position: i });
      i += 1;
      continue;
    }
    if (ch === '(') {
      tokens.push({ type: 'lparen', value: ch, position: i });
      i += 1;
      continue;
    }
    if (ch === ')') {
      tokens.push({ type: 'rparen', value: ch, position: i });
      i += 1;
      continue;
    }
    if (ch === ',') {
      tokens.push({ type: 'comma', value: ch, position: i });
      i += 1;
      continue;
    }

    // Anything else — reject with the raw character
    throw new ExpressionValidationError(
      ch, i,
      `Character "${ch}" is not allowed in expressions. Only numbers, report fields, + - * / %, parentheses, commas, and the functions ${[...ALLOWED_FUNCTIONS].join(', ')} may be used.`
    );
  }

  return tokens;
}

// ── Recursive-descent parser (grammar check only) ────────────

class Parser {
  private pos = 0;

  constructor(
    private readonly tokens: Token[],
    private readonly validFields: Set<string>
  ) {}

  private peek(): Token | undefined {
    return this.tokens[this.pos];
  }

  private next(): Token | undefined {
    return this.tokens[this.pos++];
  }

  parse(): void {
    if (this.tokens.length === 0) {
      throw new ExpressionValidationError('', 0, 'Expression must not be empty.');
    }
    this.parseExpression();
    const trailing = this.peek();
    if (trailing) {
      throw new ExpressionValidationError(
        trailing.value, trailing.position,
        `Unexpected "${trailing.value}" after end of expression.`
      );
    }
  }

  private parseExpression(): void {
    this.parseTerm();
    while (this.peek()?.type === 'op' && (this.peek()!.value === '+' || this.peek()!.value === '-')) {
      this.next();
      this.parseTerm();
    }
  }

  private parseTerm(): void {
    this.parseFactor();
    while (this.peek()?.type === 'op' && ['*', '/', '%'].includes(this.peek()!.value)) {
      this.next();
      this.parseFactor();
    }
  }

  private parseFactor(): void {
    const tok = this.next();
    if (!tok) {
      throw new ExpressionValidationError('', this.endPosition(), 'Expression ends unexpectedly.');
    }

    switch (tok.type) {
      case 'number':
        return;

      case 'op': { // unary +/- (e.g. `-quantity`)
        if (tok.value !== '-' && tok.value !== '+') {
          throw new ExpressionValidationError(tok.value, tok.position, `Unexpected operator "${tok.value}".`);
        }
        this.parseFactor();
        return;
      }

      case 'lparen':
        this.parseExpression();
        this.expectRparen();
        return;

      case 'func': {
        const afterName = this.next();
        if (!afterName || afterName.type !== 'lparen') {
          throw new ExpressionValidationError(
            tok.value, tok.position,
            `"${tok.value}" must be followed by "(...)".`
          );
        }
        // CAST(expr AS TYPE) has a type keyword as its final argument.
        if (tok.value === 'CAST') {
          this.parseExpression();
          const asTok = this.next();
          if (!asTok || !/^(as)$/i.test(asTok.value) || asTok.type !== 'ident') {
            throw new ExpressionValidationError(
              asTok?.value || '', asTok?.position ?? tok.position,
              'CAST requires the form CAST(expression AS type).'
            );
          }
          const typeTok = this.next();
          if (!typeTok || typeTok.type !== 'ident' || !/^(INTEGER|INT|REAL|FLOAT|TEXT|NUMERIC|DECIMAL)$/i.test(typeTok.value)) {
            throw new ExpressionValidationError(
              typeTok?.value || '', typeTok?.position ?? tok.position,
              'CAST target type must be one of INTEGER, REAL, TEXT, NUMERIC, DECIMAL.'
            );
          }
        } else {
          this.parseExpression();
          while (this.peek()?.type === 'comma') {
            this.next();
            this.parseExpression();
          }
        }
        this.expectRparen();
        return;
      }

      case 'ident': {
        if (!this.validFields.has(tok.value)) {
          throw new ExpressionValidationError(
            tok.value, tok.position,
            `Unknown field "${tok.value}" — identifiers must be fields of this report or computed columns defined alongside this one.`
          );
        }
        return;
      }

      default:
        throw new ExpressionValidationError(
          tok.value, tok.position,
          `Unexpected token "${tok.value}" in expression.`
        );
    }
  }

  private expectRparen(): void {
    const tok = this.next();
    if (!tok || tok.type !== 'rparen') {
      throw new ExpressionValidationError(
        tok?.value || '', tok?.position ?? this.endPosition(),
        'Missing closing parenthesis.'
      );
    }
  }

  private endPosition(): number {
    const last = this.tokens[this.tokens.length - 1];
    return last ? last.position : 0;
  }
}

// ── Public API ───────────────────────────────────────────────

/**
 * Validate a computed-column expression against the safe grammar.
 *
 * @param expression  Raw expression string from the config.
 * @param validFields Field names available to the expression: every entity
 *                    field plus all computed-column names of the config.
 * @throws ExpressionValidationError (map to HTTP 400 at the controller).
 */
export function validateExpression(expression: string, validFields: Set<string>): void {
  const trimmed = typeof expression === 'string' ? expression.trim() : '';
  if (trimmed.length === 0) {
    throw new ExpressionValidationError('', 0, 'Expression must not be empty.');
  }
  if (trimmed.length > 500) {
    throw new ExpressionValidationError('', 0, 'Expression must be 500 characters or less.');
  }

  const upper = trimmed.toUpperCase();
  for (const commentMarker of ['--', '/*', '*/']) {
    if (upper.includes(commentMarker)) {
      throw new ExpressionValidationError(commentMarker, upper.indexOf(commentMarker), 'SQL comments are not allowed in expressions.');
    }
  }
  if (trimmed.includes(';')) {
    throw new ExpressionValidationError(';', trimmed.indexOf(';'), 'Semicolons are not allowed in expressions.');
  }

  const tokens = tokenize(trimmed);
  new Parser(tokens, validFields).parse();
}

/**
 * Validate every computed column in a report config.
 * Convenience wrapper used by the query engine and both controller paths.
 */
export function validateConfigExpressions(config: {
  computedColumns?: Array<{ name: string; expression: string }>;
}, entityFields: Set<string>): void {
  if (!Array.isArray(config.computedColumns)) return;

  // Expressions may reference entity fields AND other computed columns.
  const scope = new Set(entityFields);
  for (const cc of config.computedColumns) {
    scope.add(cc.name);
  }
  for (const cc of config.computedColumns) {
    validateExpression(cc.expression, scope);
  }
}
