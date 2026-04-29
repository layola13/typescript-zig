export function add(a: number, b: number): number {
  return a + b;
}

export class Greeter {
  greeting: string;
  constructor(message: string) {
    this.greeting = message;
  }
  greet(): string {
    return "Hello, " + this.greeting;
  }
}

export interface User {
  name: string;
  age: number;
}
