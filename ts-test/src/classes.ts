export class Animal {
  name: string;
  age: number;
  
  constructor(name: string, age: number) {
    this.name = name;
    this.age = age;
  }
  
  speak(): string {
    return `${this.name} makes a sound`;
  }
}

export interface Pet extends Animal {
  owner: string;
}
